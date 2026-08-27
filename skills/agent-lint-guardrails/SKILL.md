---
name: agent-lint-guardrails
description: "Use when setting up or tightening automatic code-quality guardrails on a repo where agents open most of the pull requests — cyclomatic-complexity budgets, file/function size caps, the React 'deslop' hook bans, and a coverage ratchet. Rules that are draconian for a human are the right ceiling for an agent: they cap the blast radius of vibe-coded churn and keep diffs reviewable. Covers the oxlint config, the warn-first-then-ratchet rollout strategy that lets budgets ship green across a whole fleet at once, and the hard gotchas (oxlint has no no-restricted-syntax, parse errors can't be downgraded, most repos have Allow-auto-merge off). Triggers: 'add lint budgets', 'cyclomatic complexity limit', 'oxlint', 'deslop', 'ban useEffect/useState', 'coverage ratchet', 'lint rules for agents', 'stop the slop', 'roll lint to all my repos'."
---

# agent-lint-guardrails

Rules too strict for a human are the right ceiling for an agent. An agent will happily write a
300-line function with a cyclomatic complexity of 40; a human reviewer will not catch it at 2am
across 40 repos. So move the ceiling into the linter, run it in CI, and let the agent self-correct
before the PR ever reaches you.

## The budgets (oxlint)

Use **oxlint** (`oxc`, https://oxc.rs) — one fast binary, no plugin install, runs in CI and
pre-commit. Default agent budgets:

| Rule | Cap | Why |
|---|---|---|
| `complexity` | 10 | one function, one job — split, don't raise the cap |
| `max-lines` | 300 | a file over 300 lines is two files |
| `max-lines-per-function` | 50 | a function over 50 lines hides its own bugs |
| `max-params` | 4 | more than 4 params → pass an object |
| `max-depth` | 4 | deep nesting is un-reviewable |
| `max-nested-callbacks` | 4 | same |
| coverage | ratchet | every PR must not lower codecov; new code carries tests |

The canonical `.oxlintrc.json` + workflow live in `~/oxlint-rollout/` on the author's machine.

## Ship it warn-first, then ratchet — the only way to fan out

Strict-as-**error** is a trap for an existing fleet. Measured on one real repo (offrouter, 702 TS
files): strict budgets produced **~470 blocking errors** — 266 complexity, 121 long-function, 42
big-file, plus hundreds of `correctness`/`perf` category errors. Multiply across 40 repos and you
have a multi-week refactor campaign, not a rollout — and every PR red-CIs and blocks its own merge.

So: **every rule ships as `warn`.** CI stays green, the PR auto-merges, and the violation counts
become visible on every run. Then ratchet per repo over time — promote `correctness` to error
first (real bugs), then the size/complexity budgets as you burn them down. A simple counter beats
a grand plan: pick one repo, fix its top violations, flip those rules to error, move on.

## Three gotchas that will bite you (all learned the hard way)

1. **oxlint has NO `no-restricted-syntax`.** The React "deslop" hook bans (below) CANNOT ride on
   oxlint — the config fails to parse with `Rule 'no-restricted-syntax' not found`. Budgets live in
   oxlint; the React bans live in **eslint**. Two linters, two jobs.
2. **Parse errors can't be downgraded by config.** oxlint keeps a couple of parser-level errors
   (`Empty parenthesized expression`, missing-semicolon on some TSX) at error severity no matter
   what `categories` say — so the job exits 1 even in an all-`warn` config. Fix: the CI step runs
   `bunx oxlint@^1 --config .oxlintrc.json || true` during the warn-first phase. Drop the `|| true`
   when you ratchet that repo to enforcement.
3. **Most personal repos have "Allow auto-merge" OFF.** `gh pr merge --auto` then fails. Either the
   PR is immediately mergeable (direct `--squash`) or it is BLOCKED by a required review — do NOT
   admin-bypass a required review to land a lint config; that defeats the guardrail. Leave it for
   the one-click approval.

## React feature code — the deslop ban-list (eslint, warn-first)

In **feature** code, derive state; do not store it. Ban via eslint `no-restricted-syntax`
(CallExpression selectors) at `warn`, then flip to `error`:

- No `useState` / `useEffect` / `useLayoutEffect` / `useReducer` / `useSyncExternalStore` — derive
  from the backend + URL params; load data through a loader-initiated `useQuery` (tanstack router
  `preload="instant"` makes the route instant).
- No `useMemo` / `useCallback` — the React Compiler handles memoization.
- No overzealous destructuring; no type casting outside tests.

These are style, not correctness — an `eslint-disable` with a one-line reason is the rare escape
hatch, never the default fix.

## Rollout mechanics (fleet-scale)

- **Fan-out unit = 2 self-contained files** (`.oxlintrc.json` + a standalone `oxlint.yml` that runs
  `bunx oxlint`), independent of each repo's existing turbo/eslint pipeline. Uniform, minimal blast
  radius, no per-repo bespoke wiring.
- **No local clone needed** — create the branch and both files through the `gh` contents API
  (the token needs `workflow` scope; a git *push* of a workflow file works, but the contents-API
  edit of a workflow is classifier-gated, so patch workflows via clone+push).
- **Skip forks and empty scaffolds.** `isFork==true` → never lint someone else's code. A 3–4 KB
  repo is an empty scaffold — skip it.
- **Deploy guard before merge.** Check whether the PR's base branch has a deploy/release workflow
  triggered by push to it. Merge freely where it deploys to staging or a demo; hold (or retarget to
  the staging branch) where merging the default branch deploys production.

## Beyond lint — the fuller agentic guardrail stack

Lint budgets are one layer. The complete stack for high-quality agent-authored code:

1. **Lint budgets** (this skill) — complexity, size, deslop.
2. **Coverage ratchet** — a CI gate that fails when a PR lowers coverage; new code carries tests.
3. **Asset/bundle byte budget** — a size check on built JS/CSS so an agent can't 3× the bundle.
4. **Typecheck as a required check** — `tsc --noEmit`, no `any` (oxlint `no-explicit-any`).
5. **Secret + dependency scanning** — gitleaks on every PR; Dependabot/`bun update` cadence.
6. **A review gate** — an LLM council or `claude-review` that must approve, plus one human click on
   protected branches. Do not let agents bypass it.
7. **CI economics** — at agent PR volume, add concurrency-cancel + path filters (see the
   `ci-cost-at-agent-scale` skill) before the bill surprises you.

Roll each out the same way: warn/advisory first across the fleet, then ratchet to blocking per repo.
