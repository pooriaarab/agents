# Boxes

Personal repos run agent work on ascii.dev Boxes. A Box is a remote Ubuntu VM. Each git worktree gets one. The goal is a fast, correctly-configured build environment for a high-volume agent fleet.

This work makes Boxes fast and correct. Every number was measured on real hardware on 2026-08-28.

## Why

Worktree creation took ~77 seconds end to end. The Box came up misconfigured. Secrets did not reach the build. The Turborepo remote cache never hit. Every agent paid the same cold install cost.

ascii.dev is a third-party provider. This setup is personal-repos-only. Never put Mozilla, work, or proprietary source on a Box.

## What was wrong and what changed

### Provisioning was not the bottleneck

A cold Box reaches `ready` in 0.8–1.3s and first usable command in 2.0–2.6s. The 77s comes from elsewhere.

Measured end to end for replytosocial (693 files, 3.9 MiB) via the crabbox hook:

- lease (box new + provision): 14.3s
- bootstrap: 10.1s
- sync (rsync + ssh + finalize + git_seed + manifest_write + fingerprint_remote + prune): 48.7s
- command (apt check + bun install, bun install itself 7.2s): 14.9s
- total: 1m16.8s, end to end 1m38.3s

Two thirds of the wait is rsyncing the worktree to the box. Dependency install is 15s of 77s. A snapshot that only caches `node_modules` fixes the smaller half.

A warm Box is slower to first usable command, not faster. A cold Box from `base` is usable in 2.0–2.6s. A warm Box restored from a 651 MB snapshot is ready in 0.9–1.0s but usable only in 6.6–9.1s. It restores the filesystem. It wins overall because it skips install, not because it boots faster.

### Secrets went to the wrong path

crabbox copies gitignored files to the box before install. With no `.crabbox-secrets` manifest it copies the worktree root only. For Content Rabbit the 5-key root `.env.local` went up and the 221-key `apps/website/.env.local` did not. The box installed cleanly and failed at runtime.

Each repo now has a `.crabbox-secrets` manifest. It lists paths only. It holds no values. It is committed.

| Repo | Manifest paths | PR |
|---|---|---|
| content-rabbit | `.env.local`, `apps/website/.env.local` | #921 |
| replytosocial | `.env.local`, `backend/.dev.vars` | #206 |
| imecore | `.env.local`, `apps/web/.env.local`, `apps/web/cloudflare/app-worker/.dev.vars` | #98 |
| popcornteam | `.env.local` | #252 |

Two decisions:

- replytosocial excludes `backend/.env.local`. It holds live Stripe keys and the production BYOK encryption key. Nothing in `backend/src` or `scripts/` reads its six names at build. The runtime reads the same names from `.dev.vars`. A Box is a third-party VM. It does not need live keys to build.
- imecore lists `apps/web/.env.local` and `apps/web/cloudflare/app-worker/.dev.vars` even though the contents are identical. Next.js reads one. Wrangler reads the other. Both are required.

### The Turborepo remote cache was configured but unused

Credentials already reached the box inside the root `.env.local`. Nothing exported them and the remote script never ran turbo. Every build was cold.

Measured on a real box:

| Run | State | Result |
|---|---|---|
| A | as crabbox leaves it | `Remote caching disabled`, 0 cached, 6.022s |
| B | `TURBO_*` exported | `Remote caching enabled`, miss, populates remote, 6.718s |
| C | local `.turbo` deleted | 2 hits from remote, 605ms, `FULL TURBO` |

Run C deletes the local cache first. The hit can only come from the remote. The fix is one named `box env` per repo carrying `TURBO_API`, `TURBO_TOKEN`, and `TURBO_TEAM`. The box receives them at boot. Verified in the environment.

### crabbox could not start a warm box

crabbox shells out to `box` but forwards only three flags: `-ascii-box-base-url`, `-ascii-box-cli`, and `-ascii-box-workdir`. It has no way to pass `--environment` or `--from`. Every crabbox warmup started from the bare `base` image.

`scripts/box-warm-shim` fills the gap. It stands in for the `box` binary. It injects the two flags on `new`. It passes every other subcommand through. No crabbox change is required.

Verified end to end: box pinned to environment `replytosocial` v5, 732 MB of `node_modules` restored, `TURBO_*` present, warmup 17.1s.

### The base image already has the toolchain

crabbox apt-installs `curl`, `git`, `build-essential`, `python3`, `pkg-config`, then installs bun. All of it is already present: node 24, bun 1.3.14, git, gh, rg, jq, docker, ffmpeg, Chrome, plus Go, Rust, Java, Ruby, PHP and more. That work is waste on every attach.

## Steps to repeat

1. Add a `.crabbox-secrets` manifest to the repo. List every secret file the build needs, one path per line. Commit it.

2. Create one `box env` per repo. Set the three Turborepo vars and disable credential forwarding:

   ```bash
   box env create <repo> --box-credentials false --agents-credentials false
   box env set-var <repo> TURBO_API <value>
   box env set-var <repo> TURBO_TOKEN <value>
   box env set-var <repo> TURBO_TEAM <value>
   ```

3. Build a warm snapshot. Start a box from the repo, install deps, scrub secrets, then save:

   ```bash
   box new --environment <repo>
   # install deps on the box
   # remove .env.local and .dev.vars from the box filesystem
   box snapshot <id> <repo>-ready
   ```

   The environment injects config at boot. The snapshot holds only `node_modules` and other build artifacts.

4. Wire the shim. Point crabbox at `scripts/box-warm-shim` via `-ascii-box-cli`. The shim injects `--from <repo>-ready --environment <repo>` on `new`. Refresh a snapshot by saving the same name again. Boxes already deployed from the old name are unaffected.

5. Check limits before a fan-out:

   ```bash
   box limits --json   # check starts.hour.remaining
   ```

## Trade-offs

### Warm boxes trade boot speed for install savings

A warm box reaches first usable command in 6.6–9.1s versus 2.0–2.6s for a cold box. It restores more filesystem. It wins because it skips `bun install`, not because it starts faster. Do not quote `ready` (0.9–1.0s) as time to work.

### Snapshots and zero data retention are mutually exclusive

A named snapshot is a filesystem image. Zero data retention (ZDR) queues named snapshots for deletion and blocks new ones. You must choose. This setup keeps snapshots and leaves ZDR off.

### Box environments that hold app secrets are readable in plaintext

`box env list` prints stored secret files in plaintext. Anyone who can run the CLI can read them. App secrets stay out of box environments for that reason. Environments here carry `TURBO_*` only. App config travels per run via the crabbox sync path.

### Webhooks cannot drive idle reaping

`box webhook` fires on `ready`, `error`, `archived`, and `hydrated` only. There is no idle or activity event. Lifecycle hooks cannot drive an idle reaper. `box-reap` stays the reaping mechanism. It measures CPU and load and prefers a heartbeat file. A box pegged at 100% CPU still reports idle, so reaping on state alone is wrong.

### Snapshot count caps the strategy

The account holds at most 10 named snapshots. One per repo works. One per worktree does not. Refresh by saving the same name again. The old artifact releases and deployed boxes keep running.

## Gotchas

- `sizeBytes` on a named snapshot is the incremental delta, not the restored size. One snapshot reported 32,830 bytes and restored 651 MB. Incremental snapshots share a chain. Deploy from the name and measure the box.

- The ascii GitHub token is a scoped app token. `box env add-repo` 404s on any repo not connected in the ascii dashboard. An in-box `gh repo clone` of the same repo also fails. Connect the repo in the dashboard first, or push the source from the laptop.

- The shim must parse `box` arguments correctly. crabbox calls `box --no-update --json --api-url https://ascii.dev new --ttl 900`. A naive "first bare word" scan picks up `https://ascii.dev` as the subcommand. The shim then passes through and you get a cold box that looks fine.

- crabbox runs `box` with `HOME` pointed at its own state directory. `$HOME/.ascii/bin/box` does not exist in that context. Resolve the real home from the OS user.

- A green exit proves nothing. Three separate steps exited 0 while doing nothing: the shim passing through on a mis-parsed subcommand, `box new --json` emitting JSONL that a single-object parser dropped (which leaked three billing boxes), and a worker producing zero bytes in 20 minutes. Verify by inspecting the result.

- Box has no idle timer. The auto-stop TTL counts from creation or resume, never from last activity. The default is 1 hour, max 30 days. At expiry a box stops and snapshots. It is not deleted. The caller must `box stop`.

- `box new --json` emits JSONL, not a single JSON object. A parser that expects one object drops boxes silently.

- `box exec` caps at 600s. Use `box exec --detach` for longer work. Poll with `box exec --status <pid>`. Logs live at `~/.ascii/processes/<pid>.log`. Detached processes do not survive stop, resume, or fork.

- `box host` survives resume as a stable URL. `box forward` does not. `box forward` is an ephemeral local TCP tunnel.

- Plan `box_20` allows 100 concurrent boxes but only 50 starts per hour and 150 per day. The hourly start ceiling limits an agent fleet, not the concurrency cap.

## What to adopt and what to skip

Adopt: `box env` (one per repo), `box snapshot` / `--from` (the dep cache, via the shim), `box exec --detach`, `box scp`, `box limits`.

Skip: `box webhook` (no idle event), `box data-retention` (conflicts with snapshots), `box host` / `box forward` for build boxes, `box org` / `box team` (single-user account), `box desktop`, `box api-key` automation, `--type large` (twice the price, not measurably faster).

## Still open

- Content Rabbit has no warm snapshot. The repo is not connected to the ascii GitHub app, so the box cannot clone it. Connect it in the dashboard or seed the snapshot by pushing the tree from the laptop.

- The 49s rsync is the dominant cost. A snapshot that already contains the repo checkout would turn the full sync into a delta. That win is larger than the install saving.

- The shim is not yet wired into `crabbox-attach.sh` for every repo.
