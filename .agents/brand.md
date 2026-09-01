# agents brand

`agents` is the public hub for a portable AI workspace. One source tree supplies shared configuration to several agent clients.

Use this file for naming, voice, and trust rules. Use `.agents/design.md` for document, CLI, and configuration patterns.

## Name

- Write the repository and workspace name as `agents`.
- Use `agents` for the wrapper command.
- Use `Fleet` for the vendored engine.
- Use the client names `Claude Code`, `Codex`, `Gemini`, `Kimi`, and `pi`.
- Do not describe `agents` as a hosted service or graphical product.

## Purpose

The repository provides a portable source of truth for rules, skills, commands, hooks, settings, MCP declarations, and memory guidance.

The engine validates the source, backs up replaced files, links managed content, and restores the prior state after a failed apply.

## Voice

- Lead with the action or result.
- Use direct, literal language.
- Name the command, file, or state that supports a claim.
- State destructive effects before the command that causes them.
- Separate required steps from optional choices.
- Avoid slogans, model promotion, and unsupported guarantees.

## Trust boundary

This public repository contains portable configuration and blank examples. Personal rules, credentials, host details, and private memory stay outside it.

- Store secret names in `mcp/required-secrets.txt`, never secret values.
- Store managed credentials through `bin/agents auth set NAME`.
- Keep host details in ignored local overlays.
- Keep Claude-Mem databases and sessions local unless the user requests shared memory.
- Run `bin/agents check` before applying or publishing changes.

## Repository family

| Repository | Responsibility |
| --- | --- |
| `agents` | Portable workspace hub and Fleet engine |
| `skills` | Reusable agent behaviors |
| `clis` | API command-line bindings |
| `commands` | Slash commands and shortcuts |
| `scripts` | Operational automation |
| `prompts` | Refined prompts |

Each category repository owns its content. The hub composes that content without changing its meaning.

## Canonical sources

- Product overview: `README.md`
- Safe setup contract: `SETUP_WITH_AN_AGENT.md`
- Recovery flow: `RECOVERY.md`
- Host boundary: `hosts/README.md`
- MCP boundary: `mcp/README.md`
- Memory format: `memory/README.md`
