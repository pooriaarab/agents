#!/bin/bash
set -uo pipefail

# Pre-Push Safety Gate
# Prevents accidental pushes to protected branches and runs a quick validation
# before code leaves the local machine.
#
# Hook: PreToolUse (matcher: Bash)
# Receives JSON on stdin with tool_input.command
#
# Three things this gate has to get right, each learned from a false result:
#
# 1. WHICH REPO. The checks used a bare `git branch --show-current`, which
#    resolves against the shell's cwd. Claude Code's Bash tool resets cwd
#    between calls, so `cd <worktree> && git push` arrived with the shell still
#    in the primary checkout; with that on main, every push from every worktree
#    was rejected as "you are on main". The target repo is now resolved from the
#    command and every git call is scoped to it.
# 2. GIT'S GLOBAL OPTIONS. Matching the literal adjacent string "git push" missed
#    `git -C /path push ...` entirely, so that form skipped the gate including the
#    protected-branch block. Global options are stripped before matching.
# 3. COMMAND POSITION. Matching "git push" anywhere in the text fired on a
#    `git commit` whose message merely QUOTED a push command. Detection is
#    anchored to a real command position, and the refspec/force checks run only
#    against the extracted push invocations.

INPUT=$(cat)

# --- Parse the payload once ------------------------------------------------
# Line 1 is the target repo dir; the remaining lines are the push invocations
# found in the command (one per line), already stripped of git's global options.
# The python source is fed through a QUOTED heredoc, never `python3 -c "..."`.
# In a double-quoted bash string the backticks in a code comment become command
# substitution: a comment mentioning `D=/repo; cd $D` actually RAN `cd /repo`
# and printed "cd: /repo: No such file or directory" on every push. A quoted
# heredoc disables all expansion, so the python body is inert text.
# The python source is passed as a SINGLE-quoted -c argument. Two constraints
# force this exact shape:
#   - It must not be double-quoted. In a double-quoted bash string the
#     backticks in a code comment become command substitution: a comment
#     mentioning a `cd /repo` example actually RAN it, printing
#     "cd: /repo: No such file or directory" on every push.
#   - It must not use a heredoc. macOS ships bash 3.2, which cannot parse a
#     heredoc inside $( ), so `PY=$(cat <<EOF ...)` is a syntax error here.
# Single quotes disable every expansion, so the body stays inert text. The body
# therefore contains NO apostrophe -- chr(39) builds one where a regex needs it.
PARSED=$(CLAUDE_PREPUSH_INPUT="$INPUT" python3 -c 'import json, os, re

try:
    data = json.loads(os.environ.get("CLAUDE_PREPUSH_INPUT") or "{}")
except Exception:
    data = {}

command = data.get("tool_input", {}).get("command", "") or ""
fallback = data.get("cwd") or os.getcwd()

SQ = chr(39)
PATH_RE = "(\"([^\"]+)\"|{q}([^{q}]+){q}|([^\\s;&|]+))".format(q=SQ)
GLOBAL_OPT = (
    "(?:-C\\s+\\S+|-c\\s+\\S+|--git-dir(?:=|\\s+)\\S+"
    "|--work-tree(?:=|\\s+)\\S+|--namespace(?:=|\\s+)\\S+"
    "|--exec-path(?:=|\\s+)\\S+|--no-pager|--no-replace-objects"
    "|--literal-pathspecs|--bare|--paginate|-p|-P)"
)
# A command starts at the beginning, or after a separator. Anchoring here is
# what keeps a quoted push inside a commit message from tripping the gate.
CMD_START = "(?:^|[\\n;&|]|&&|\\|\\|)[ \\t]*"

PROTECTED = {"main", "master", "production", "release"}


def unquote(match):
    for group in match.groups()[1:]:
        if group:
            return group
    return match.group(1)


def target_dir():
    chosen = None
    # An explicit -C on the git invocation is the most specific signal; a later
    # cd in the chain otherwise wins. A path that is not a real directory is
    # ignored, so this FAILS CLOSED: a typo, a shell variable, or a command
    # substitution the hook cannot expand statically falls back to the payload
    # cwd rather than skipping the checks.
    for pattern in (
        "git\\s+(?:" + GLOBAL_OPT + "\\s+)*?-C\\s+" + PATH_RE,
        CMD_START + "cd\\s+" + PATH_RE,
    ):
        for m in re.finditer(pattern, command):
            expanded = os.path.expanduser(os.path.expandvars(unquote(m)))
            if os.path.isdir(expanded):
                chosen = expanded
    return chosen or fallback


def push_invocations():
    # Strip global options so the subcommand sits directly after git.
    normalized = re.sub("\\bgit\\s+(?:" + GLOBAL_OPT + "\\s+)+", "git ", command)
    found = []
    for m in re.finditer(CMD_START + "(git\\s+push\\b[^\\n;&|]*)", normalized):
        found.append(" ".join(m.group(1).split()))
    return found


def destinations(invocations):
    # Refspec DESTINATIONS across all push invocations. The gate has to judge
    # where a push LANDS, not which branch happens to be checked out.
    # "push origin HEAD:main" and "push origin main" both land on main and must
    # be blocked; "push origin origin/main:refs/heads/live" lands on live and is
    # fine even while the repo sits on main.
    # Push options that take their value as a SEPARATE token (not attached via
    # `=`), e.g. `-o ci.skip`. Left unhandled, the value token is mistaken for
    # a refspec destination, which sets HAS_REFSPEC=yes and skips both the
    # protected-destination check and the checked-out-branch fallback below.
    OPT_WITH_ARG = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
    dsts = []
    for invocation in invocations:
        tokens = invocation.split()[2:]  # drop the leading git push
        remote_seen = False
        skip_next = False
        for token in tokens:
            if skip_next:
                skip_next = False
                continue
            if token.startswith("-"):
                if token in OPT_WITH_ARG:
                    skip_next = True
                continue
            if not remote_seen:
                remote_seen = True  # first bare token is the remote
                continue
            spec = token.lstrip("+")
            if ":" not in spec and spec in ("HEAD", "@"):
                # No colon: this is a SOURCE-only refspec. `push origin HEAD`
                # pushes the checked-out branch to a same-named remote branch
                # -- it is not a literal destination named "HEAD"/"@". Leave
                # it uncounted so HAS_REFSPEC falls back to the
                # checked-out-branch gate, which resolves the real branch.
                continue
            dst = spec.split(":")[-1] if ":" in spec else spec
            if dst.startswith("refs/heads/"):
                dst = dst[len("refs/heads/"):]
            if dst.startswith("refs/tags/") or dst == "":
                continue
            dsts.append(dst)
    return dsts


invocations = push_invocations()
dsts = destinations(invocations)

print(target_dir())
print("HAS_REFSPEC=" + ("yes" if dsts else "no"))
print("PROTECTED_DST=" + ("yes" if any(d in PROTECTED for d in dsts) else "no"))
for invocation in invocations:
    print(invocation)' 2>/dev/null)

TARGET_DIR=$(printf '%s\n' "$PARSED" | sed -n 1p)
HAS_REFSPEC=$(printf '%s\n' "$PARSED" | sed -n 2p | cut -d= -f2)
PROTECTED_DST=$(printf '%s\n' "$PARSED" | sed -n 3p | cut -d= -f2)
PUSH_CMDS=$(printf '%s\n' "$PARSED" | tail -n +4)

# Nothing that actually pushes -- let it through.
if [ -z "$PUSH_CMDS" ]; then
    exit 0
fi

if [ -z "$TARGET_DIR" ] || [ ! -d "$TARGET_DIR" ]; then
    TARGET_DIR=$(pwd)
fi

# Every git call below is scoped to the resolved repo.
git_t() {
    git -C "$TARGET_DIR" "$@"
}

REPO_ROOT=$(git_t rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ]; then
    # Not a git repo (e.g. a scratch dir) -- nothing to validate.
    exit 0
fi

# --- Block push to protected branches (by DESTINATION refspec) ---
# The text grep stays as a second line of defense in case the parse degrades.
if [ "$PROTECTED_DST" = "yes" ] || echo "$PUSH_CMDS" | grep -qE "(origin|upstream)[[:space:]]+(main|master|production|release)\b"; then
    echo "[Pre-Push] BLOCKED: Direct push to a protected branch detected." >&2
    echo "Use a feature branch and create a PR instead." >&2
    exit 2
fi

BRANCH=$(git_t branch --show-current 2>/dev/null || echo "")

# --- Force-push rules ---
if echo "$PUSH_CMDS" | grep -qE -- '(--force|--force-with-lease|-f)\b'; then
    if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
        echo "[Pre-Push] BLOCKED: Force push to $BRANCH is not allowed." >&2
        echo "[Pre-Push] Repo: $REPO_ROOT" >&2
        exit 2
    fi
    echo "[Pre-Push] Warning: Force pushing to ${BRANCH:-unknown} ($REPO_ROOT)." >&2
fi

# --- Refuse to push from a protected branch ---
# Only when the push carries NO explicit refspec, i.e. it would push the
# checked-out branch. With a refspec the destination is what matters, and that
# was already judged above -- otherwise a legitimate
# `git push origin origin/main:refs/heads/live` is rejected for the irrelevant
# reason that the repo happens to be on main.
if [ "$HAS_REFSPEC" = "no" ] && { [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; }; then
    echo "[Pre-Push] BLOCKED: '$REPO_ROOT' is on '$BRANCH'. Switch to a feature branch first." >&2
    echo "Create a branch with: git -C '$REPO_ROOT' checkout -b <branch-name>" >&2
    exit 2
fi

# --- Warn about work that will not be included ---
if [ -n "$(git_t status --porcelain 2>/dev/null)" ]; then
    echo "[Pre-Push] Warning: You have uncommitted changes that won't be included in this push." >&2
fi

# --- Skip typecheck for merge commits (e.g. merging main into a feature branch) ---
if git_t log -1 --format='%P' HEAD 2>/dev/null | grep -q ' '; then
    echo "[Pre-Push] HEAD is a merge commit -- skipping typecheck." >&2
    exit 0
fi

# --- Skip typecheck on a stale branch (pre-existing mismatches are not ours) ---
BEHIND_COUNT=$(git_t rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
if [ "$BEHIND_COUNT" -gt 10 ]; then
    echo "[Pre-Push] Warning: Branch is $BEHIND_COUNT commits behind main. Consider rebasing." >&2
    echo "[Pre-Push] Skipping typecheck -- stale branch may have pre-existing type mismatches." >&2
    exit 0
fi

# --- Quick typecheck for Node.js projects (only errors in NEW changes) ---
if [ -f "$REPO_ROOT/package.json" ]; then
    REMOTE_BRANCH=$(git_t rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")
    if [ -n "$REMOTE_BRANCH" ]; then
        # Compare against what is already on the remote branch, not origin/main,
        # so pre-existing errors in already-pushed commits do not block. For a
        # force-push (rebase) only the latest commit's files are checked.
        if echo "$PUSH_CMDS" | grep -qE -- '(--force|--force-with-lease|-f)\b'; then
            CHANGED_TS=$(git_t diff --name-only HEAD~1 2>/dev/null | grep -E '\.tsx?$' || true)
        else
            CHANGED_TS=$(git_t diff --name-only "$REMOTE_BRANCH" 2>/dev/null | grep -E '\.tsx?$' || true)
        fi
        if [ -n "$CHANGED_TS" ] && grep -q '"typecheck"' "$REPO_ROOT/package.json" 2>/dev/null; then
            echo "[Pre-Push] Running quick typecheck in $REPO_ROOT..." >&2
            TS_OUTPUT=$(cd "$REPO_ROOT" && npm run typecheck 2>&1 || true)
            if echo "$TS_OUTPUT" | grep -q "error TS"; then
                # Only block on errors in files WE changed.
                RELEVANT_ERRORS=""
                while IFS= read -r changed_file; do
                    BASENAME=$(basename "$changed_file")
                    FILE_ERRORS=$(echo "$TS_OUTPUT" | grep "error TS" | grep -F "$BASENAME" || true)
                    if [ -n "$FILE_ERRORS" ]; then
                        RELEVANT_ERRORS="${RELEVANT_ERRORS}${FILE_ERRORS}\n"
                    fi
                done <<< "$CHANGED_TS"
                # Generated/build-time modules are not real failures here.
                FILTERED_ERRORS=$(echo -e "$RELEVANT_ERRORS" | grep -v "_generated/" | grep -v "Cannot find module" || true)
                if [ -n "$FILTERED_ERRORS" ]; then
                    echo "[Pre-Push] BLOCKED: Typecheck errors in files you changed:" >&2
                    echo -e "$FILTERED_ERRORS" | head -10 >&2
                    exit 2
                elif [ -n "$RELEVANT_ERRORS" ]; then
                    echo "[Pre-Push] Typecheck has module-resolution errors (likely generated/build-time files), proceeding." >&2
                else
                    echo "[Pre-Push] Typecheck has pre-existing errors (not in your changes), proceeding." >&2
                fi
            else
                echo "[Pre-Push] Typecheck passed." >&2
            fi
        fi
    fi
fi

exit 0
