# agents

My portable AI workspace. One `.agents` folder is the single source of truth for how I run agent CLIs — Claude Code, Codex, Gemini, Kimi, and pi. The folder is symlinked into each tool, so every agent reads the same skills, commands, scripts, and prompts.

Idea credit: [Cathryn Lavery](https://twitter.com/cathrynlavery) — keep your AI setup in one portable folder, so a laptop crash costs you nothing.

## Layout

```
.agents/
  skills/     reusable agent behaviors
  commands/   slash commands and shortcuts
  scripts/    automations that run my ops
  prompts/    prompts I have refined
```

## Part of my AI workspace

The [`agents`](https://github.com/pooriaarab/agents) repo is the hub — a portable `.agents` folder symlinked into every agent CLI.

| Repo | What |
|---|---|
| [agents](https://github.com/pooriaarab/agents) | The hub — portable `.agents` workspace |
| [skills](https://github.com/pooriaarab/skills) | Reusable agent skills |
| [clis](https://github.com/pooriaarab/clis) | Working CLIs for ad-platform APIs |
| [commands](https://github.com/pooriaarab/commands) | Slash commands and shortcuts |
| [scripts](https://github.com/pooriaarab/scripts) | Automation scripts |
| [prompts](https://github.com/pooriaarab/prompts) | Refined prompts |

## Engine

The `.agents` folder is not just files — an engine symlinks it into each tool, backs up
first, and rolls back on failure, so one clone restores a whole machine. The engine is
[`fleet`](https://github.com/Bil0000/agents-fleet) (MIT), vendored under `bin/`, `lib/`,
`system/`, and `tests/`. `bin/agents` is a thin wrapper so I type `agents <cmd>`.

```bash
bin/agents check                 # validate: no secrets, no stray device paths
bin/agents apply --dry-run --host <id>
bin/agents apply --host <id>     # symlink rules, skills, commands, hooks, MCP into each tool
bin/agents enable-updates        # apply the validated `live` branch across devices
bin/agents update --host <id>
bin/agents rollback
```

A push runs `bin/agents check` and the engine tests on macOS and Linux (CI). A passing
`main` promotes to a validated `live` branch that each device applies.

This repo is the public, blank hub. My full personal configuration — rules, hook scripts,
host overlays, and memory — lives in a private backup.

## Memory

`memory/` is a portable, plain-Markdown memory store: one fact per file, indexed in
`memory/MEMORY.md`, recalled in three layers (index → grep → read). See
[`memory/README.md`](memory/README.md). This public copy ships empty.

## Recovery

Clone, validate, apply. See [`RECOVERY.md`](RECOVERY.md).

## Safety

This is the public version. Secrets, tokens, credentials, machine paths, and private data stay out of Git — see [`.gitignore`](.gitignore). The full local copy lives on my machine, not here.
