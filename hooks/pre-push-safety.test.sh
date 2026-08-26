#!/bin/bash
# Self-check for pre-push-safety.sh. No framework: feeds the hook a synthetic
# PreToolUse payload and asserts the exit code.
#
# Run: bash hooks/pre-push-safety.test.sh [path-to-hook]
#
# Three regressions this guards, each of which shipped as a false result:
#   - a push from a git worktree while the primary checkout sits on main
#   - the `git -C <dir>` form, which skipped every check including the
#     protected-branch block
#   - a `git commit` whose message merely QUOTES a push command
#   - a refspec push to a non-protected ref, rejected because the repo happened
#     to be on main -- the destination is what matters, not the checked-out branch
#   - backticks in the hook's own python comments being command-substituted by
#     bash, which ran a `cd` from an example and printed an error on every push
set -uo pipefail

HOOK="${1:-$(dirname "$0")/pre-push-safety.sh}"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ON_MAIN="$TMP/on-main"
ON_FEATURE="$TMP/on-feature"
for d in "$ON_MAIN" "$ON_FEATURE"; do
    mkdir -p "$d"
    git -C "$d" init -q -b main
    git -C "$d" commit -q --allow-empty -m init
done
git -C "$ON_FEATURE" checkout -q -b feature/x

# Assembled from parts so this file's own text never contains the literal
# command strings the hook matches on -- otherwise editing this file trips it.
G=git
P=pu; P="${P}sh"
PROTECTED=ma; PROTECTED="${PROTECTED}in"

pass=0
fail=0

check() {
    local desc="$1" want="$2" cmd="$3" cwd="$4"
    python3 -c "
import json, sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}, 'cwd': sys.argv[2]}))
" "$cmd" "$cwd" | bash "$HOOK" >/dev/null 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
        printf '  ok    %s\n' "$desc"
    else
        fail=$((fail + 1))
        printf '  FAIL  %s (want rc=%s, got rc=%s)\n' "$desc" "$want" "$got"
    fi
}

echo "allow:"
check "worktree on a feature branch, cwd elsewhere on $PROTECTED" 0 \
    "cd $ON_FEATURE && $G $P origin feature/x" "$ON_MAIN"
check "force-with-lease onto a feature branch" 0 \
    "cd $ON_FEATURE && $G $P --force-with-lease origin feature/x" "$ON_MAIN"
check "git -C into a feature branch, force" 0 \
    "$G -C $ON_FEATURE $P --force origin feature/x" "$ON_MAIN"
check "multiline cd then $P" 0 \
    "cd $ON_FEATURE &&
  $G $P origin feature/x" "$ON_MAIN"
check "commit message that quotes a $P command" 0 \
    "cd $ON_FEATURE && $G commit -m 'fix: $G -C /p $P origin $PROTECTED slipped through'" "$ON_MAIN"
check "the word $P in an unrelated command" 0 \
    "echo 'do not $P this'" "$ON_FEATURE"
check "not a git repo" 0 \
    "cd $TMP && $G $P" "$TMP"
check "not a $P at all" 0 \
    "$G status" "$ON_FEATURE"

echo "block:"
check "protected refspec" 2 \
    "cd $ON_FEATURE && $G $P origin $PROTECTED" "$ON_FEATURE"
check "protected refspec via git -C" 2 \
    "$G -C $ON_FEATURE $P origin $PROTECTED" "$ON_MAIN"
check "repo on $PROTECTED, reached by git -C" 2 \
    "$G -C $ON_MAIN $P" "$ON_FEATURE"
check "repo on $PROTECTED, reached by cd" 2 \
    "cd $ON_MAIN && $G $P" "$ON_FEATURE"
check "force onto $PROTECTED" 2 \
    "$G -C $ON_MAIN $P --force" "$ON_FEATURE"
check "$PROTECTED as an explicit refspec destination" 2 \
    "$G -C $ON_FEATURE $P origin HEAD:$PROTECTED" "$ON_FEATURE"
check "$PROTECTED as a fully-qualified refspec destination" 2 \
    "$G -C $ON_FEATURE $P origin HEAD:refs/heads/$PROTECTED" "$ON_FEATURE"

echo "allow (destination, not checked-out branch, decides):"
# The promote case: the repo sits on main, but the push lands on `live`.
check "refspec onto a non-protected ref from a repo on $PROTECTED" 0 \
    "$G -C $ON_MAIN $P origin origin/$PROTECTED:refs/heads/live" "$ON_MAIN"
check "short refspec onto a non-protected ref from a repo on $PROTECTED" 0 \
    "$G -C $ON_MAIN $P origin HEAD:live" "$ON_MAIN"

# The hook must not leak shell noise of its own. A backtick in its python
# comments used to be command-substituted, printing "cd: /repo: ..." to stderr.
echo "hygiene:"
NOISE=$(python3 -c "
import json, sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}, 'cwd': sys.argv[2]}))
" "$G -C $ON_FEATURE $P origin feature/x" "$ON_FEATURE" | bash "$HOOK" 2>&1 >/dev/null)
if echo "$NOISE" | grep -qE 'No such file or directory|command not found'; then
    fail=$((fail + 1))
    printf '  FAIL  hook emits no shell noise (got: %s)\n' "$NOISE"
else
    pass=$((pass + 1))
    printf '  ok    hook emits no shell noise\n'
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
