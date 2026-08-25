# Recovery

How the portable setup restores on a new or wiped machine. This public hub ships blank —
the real content lives in a private backup — but the flow is the same.

## Prerequisites

- macOS or Linux
- Git, Bash, Python 3.11+, Node.js 20.12+
- Claude Code and/or Codex installed and logged in

## Steps

1. **Clone** the repo into your `.agents` folder.

   ```bash
   git clone <repo-url> ~/Documents/Personal/.agents
   cd ~/Documents/Personal/.agents
   ```

2. **Validate.** Rejects secrets and device paths outside `hosts/`.

   ```bash
   bin/agents check
   ```

3. **Preview, then apply.** Symlinks rules, settings, skills, commands, hooks, and MCP
   manifests into each tool. Backs up first; rolls back on failure.

   ```bash
   bin/agents apply --dry-run --host <id>
   bin/agents apply --host <id>
   ```

   For a new device, add `hosts/<id>/host.toml` first (keys: `id`, `os`, `role`).

4. **Restore secrets.** MCP tokens are never in Git. Recreate them from each provider, then
   `bin/agents auth set NAME`.

5. **Enable cross-device auto-update** (optional): `bin/agents enable-updates`.

## What is NOT here (restore separately)

- MCP secrets and API tokens — from each provider's dashboard.
- Third-party skills and plugins — from their upstream sources.
- Session history, caches, databases — not backed up on purpose.
