---
name: ci-speed-diagnosis
description: "Use when CI is slow and the optimisations are already configured — a remote cache that is switched on, an actions/cache step that reports green, a suite that is already sharded. Finds out why they do nothing before you add more. Covers the measure-first order, the checklist of defects that fail silently (a secret holding an empty value, a task runner stripping its own variables from child processes, a build output glob that sweeps the incremental cache into the artifact, ref-scoped duplicate caches, restore-keys with no lockfile-independent fallback, an mtime cache strategy that checkout defeats, an upload cap in the cache server, a stale deploy of the fixed server), and the bug shape that recurs most: a mitigation calibrated for one host, applied unconditionally on every host. Adds the measurement discipline — measure a CI change in CI, report CPU time when you cannot, trust a log line over a listing API, and say whether you bought latency or machine time. Triggers: 'CI is still slow', 'the cache never hits', 'Remote caching disabled', 'our cache is empty', 'CI cache quota is full', 'make CI faster', 'why did that optimisation not help'."
---

# ci-speed-diagnosis

A slow pipeline usually has the right optimisations already. They are configured, they report
green, and they do nothing. **Diagnose the silence first. Add levers last.** Each defect below
was found this way, and each one hid behind a green check.

## When to use this

**Use this skill** when someone already added caching, a remote cache, or sharding, and CI is
still slow. Also use it before you buy a bigger runner.

**Use a sibling skill instead** when the pipeline has no caching yet
([ci-build-speed](https://github.com/pooriaarab/skills/blob/main/ci-build-speed/SKILL.md)), when you are placing jobs on runner tiers
([high-volume-ci-optimization](https://github.com/pooriaarab/skills/blob/main/high-volume-ci-optimization/SKILL.md)), or when the problem is
spend and queueing ([ci-cost-at-agent-scale](https://github.com/pooriaarab/skills/blob/main/ci-cost-at-agent-scale/SKILL.md)).

## Diagnose in this order

Do not skip a step. Each one stops you from optimising a job that does not matter.

1. **Name the metric.** Report latency and machine seconds separately. Latency is what a person
   waits for. Machine seconds are what you pay for. They move independently, so one CI number
   hides which one changed. Tool: `ci-pr-latency`.
2. **Name the critical path.** Jobs run in parallel, so wall clock is the longest job, not the
   sum. Write the per-job medians down. A win on any other job buys machine time only.
   Tool: `ci-job-timings`.
3. **Prove the caches hit.** Read the job logs for payload size, primary-key hit rate, and
   remote-cache state. A cache that restores 0 bytes still prints a green success line.
   Tool: `ci-cache-health`.
4. **Read the guards inside the long-pole job.** See the next section. This is where the time
   usually is.
5. **Only now add a lever.** Go to `ci-build-speed` and spend on the critical path.

## The bug shape that repeats: one host's mitigation, every host's cost

This was the single most common defect. Someone measures a real constraint on one machine,
writes a mitigation, and applies it unconditionally. The mitigation then runs on machines that
never had the constraint, where it is pure cost.

Four instances in one codebase:

| Guard | Written for | Cost where it does not apply |
| --- | --- | --- |
| `config.cache = false`, gated on `!dev` | an 8 GB container | kills the webpack cache on a 31 GB runner |
| `--max-old-space-size=6144` | a small container | caps the heap far below available memory |
| `cpus: 1` worker cap | a contended host | serialises a build that has cores to spare |
| a swap-creation step | a runner with no swap | writes a swapfile nothing reads |

**Symptom to look for:** a guard whose comment explains a real constraint that does not exist on
the machine now running it. The comment is usually true and usually stale.

**Rule:** gate a mitigation on the constraint, measured at run time — available memory, core
count, free disk. Do not gate it on `!dev`, on a branch name, or on a number someone typed once.

## The silent-defect checklist

| Defect | What you see | Fix |
| --- | --- | --- |
| The secret holds an empty value | one grey line, `Remote caching disabled`, then cold misses forever | Set it from a file: `gh secret set NAME -R owner/repo < file`. `--body -` does **not** read stdin. It stores the literal string `-`. |
| The task runner runs tasks in strict env mode | a nested `turbo run` never caches, because `TURBO_*` is stripped from child processes | Declare the variables in `globalPassThroughEnv`. Pass-through values do not join the cache key — a dummy token gives an identical task hash. |
| The output glob sweeps the incremental cache | `.next/**` includes `.next/cache`, so the artifact reaches 1.2 GB and its upload fails without an error. The task can then never hit. | Exclude it: `!.next/cache/**`. This took one artifact from 1.2 GB to 9.1 MB, and the job from 204s to 34s. |
| The cache server buffers the whole body | uploads over roughly 20–30 MB fail | Stream `request.body` to storage instead of `await request.arrayBuffer()`. A 50 MB object then round-trips byte-identical. |
| The deployed server is behind its source | the fix is in `main`, and production still fails | **A fix in `main` is not a fix in production.** Deploy, then re-verify against the live URL. One build stayed stale for two hours behind the fixed source. |
| Caches are ref-scoped and saved on every PR | the quota fills with byte-identical copies of one key. One repo held 9.11 GB against the 10 GB limit, of which 7 GB was duplicates. | Gate `actions/cache/save` to the default branch. Let pull requests restore through `restore-keys`. |
| Every `restore-keys` level embeds the lockfile hash | a dependency bump invalidates the primary key **and its only fallback** together | Keep one fallback level that does not depend on the lockfile. |
| Prettier runs with the default `--cache-strategy metadata` | the cache never hits in CI, because it compares mtime and `actions/checkout` rewrites every mtime | Use `--cache-strategy content`. |
| `outputFileTracingExcludes` is keyed on `"*"` | a second, mis-rooted trace pass re-reads 368 MB of JSON across 610 manifests and drops zero entries | Key it on `"next-server"`. |

## Measurement discipline

**Measure a CI change in CI.** A laptop understated an I/O-bound win by 6x — 20s locally against
65–70s in CI, because a laptop NVMe hides 368 MB of JSON reads. Contention lies in the other
direction: a baseline taken while parallel agents drove the machine to load 65–160 read 1071s for
a suite that runs in 125–131s on a quiet machine, an 8x inflation.

**When you cannot measure in CI, report CPU time (user+sys), not wall clock.** CPU time survives
contention. Wall clock does not.

**Verify behaviour, not inventory.** The cache-list API showed no entries while the job logs
proved the same caches saved and restored correctly. A log line is ground truth. A listing API is
a claim.

**Say which number you bought.** A change off the critical path buys machine time, not latency.
Both are valid. Claiming the wrong one is not.

**Parallelism beats per-job speed.** A self-hosted host was the fastest tier per job — 43s median
against 50s hosted — and still lost. It ran a fixed number of runner services, so everything else
queued: 46–52s median queue against 2s hosted.

**Sharding does not make a suite faster on its own.** Three shards took about 150s against about
128s in a single process, because every shard pays the fixed setup cost in full. Sharding buys
overlap with other checks, and survival under load: at load ~280, one process took 1090s against
301s for three shards.

## What good looks like

One campaign over four pipelines, all measured before and after: CI wall clock fell 82%, 46% and
32% on three repositories, and the local pre-push gate fell 51%. Almost none of that came from a
new lever. It came from making the configured ones actually run.

## Tools

`ci-pr-latency`, `ci-job-timings`, `ci-cache-health` and `ci-runner-audit` in
[pooriaarab/scripts](https://github.com/pooriaarab/scripts) cover steps 1 to 3 and job placement.
Run them in that order.
