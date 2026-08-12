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

## Safety

This is the public version. Secrets, tokens, credentials, machine paths, and private data stay out of Git — see [`.gitignore`](.gitignore). The full local copy lives on my machine, not here.
