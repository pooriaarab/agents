# hooks

Shared shell hooks, symlinked into each client by `bin/agents apply`.

## pre-push-safety.sh

A `PreToolUse` gate for agent-driven `git push`. Reads a JSON payload on stdin and
exits `2` to block, `0` to allow.

It blocks:

- pushing a `main` / `master` / `production` / `release` refspec
- pushing from a repo that is itself on `main` or `master`
- force-pushing onto `main` or `master`
- for Node projects, typecheck errors **in files the push actually changed**
  (pre-existing errors elsewhere do not block)

It warns on a force-push to a feature branch and on uncommitted work that the push
will leave behind.

### Resolving which repo is being pushed

The gate does not trust the shell's working directory. Agent harnesses reset cwd
between tool calls, so a push issued from a git worktree can arrive with the shell
still in the primary checkout — and reading the branch from there rejects every
worktree push as "you are on main".

The target repo is resolved from the command instead, in this order:

1. an explicit `-C <dir>` on the git invocation
2. the last `cd <dir>` in the command chain
3. the payload's `cwd`
4. `$PWD`

Resolution **fails closed**: a path the hook cannot expand statically (a shell
variable, a command substitution) falls back rather than skipping the checks, so
`D=/repo; cd $D && git push` may be blocked. Use a literal path. A safety gate does
not get a shell interpreter.

### Matching the command

Git's global options may sit between the binary and the subcommand, so the gate
strips them before matching — otherwise `git -C <dir> push` matches nothing and
skips every check. Detection is also anchored to a real command position, so a
commit message that merely quotes a push command does not trip it.

### Tests

```bash
bash hooks/pre-push-safety.test.sh
```

Builds throwaway repos on a protected and a feature branch, feeds the hook synthetic
payloads, and asserts exit codes over 13 cases. No framework. The test file assembles
its command strings from parts, because a file containing them verbatim trips the hook
it is testing.
