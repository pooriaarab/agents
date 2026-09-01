# agents design system

This is the canonical design context for repository documents, CLI output, configuration, and filesystem layout.

Read `.agents/brand.md` before changing public guidance. This repository has no hosted interface or owned production URL.

## Overview

`agents` is terminal-first and Markdown-first. Its design system makes machine operations understandable, reviewable, and recoverable.

The system covers five surfaces:

- Markdown instructions for people and agents.
- Plain-text command output.
- JSON and TOML configuration.
- A portable filesystem tree.
- Safety prompts around setup, apply, update, and recovery.

Prefer an existing repository pattern. Add a new pattern only when the current files cannot express the requirement.

## Colors

The repository defines no color palette. Documents and commands must remain complete without color.

CLI output is plain text. Use stable labels such as `host:`, `target:`, `dirty:`, `drift:`, `set`, and `missing`.

- Do not add ANSI color as the only status signal.
- Do not add brand hex values or visual color tokens.
- Let terminals, editors, and Markdown renderers control syntax colors.
- Pair every state with explicit text.

## Typography

The repository selects no font. The terminal, editor, or documentation renderer owns type rendering.

- Use ATX headings: one `#` title, then ordered `##` sections.
- Use sentence case for headings.
- Use backticks for commands, paths, keys, and literal values.
- Give fenced code blocks an accurate language when one applies.
- Keep paragraphs short and wrap prose to the local file convention.
- Use tables only for repeated field comparisons.

Never depend on bold, italics, emoji, or glyph width to communicate a required step.

## Layout

The filesystem is the primary layout system.

| Path | Role |
| --- | --- |
| `skills/` | Shared skill packages |
| `commands/` | Shared slash commands |
| `hooks/` | Shared shell hooks |
| `rules/` | Common and client rules |
| `settings/` | Portable client settings |
| `mcp/` | MCP declarations, runners, and secret names |
| `hosts/` | Ignored machine overlays |
| `memory/` | Portable Markdown memory guidance |
| `bin/`, `lib/`, `system/`, `tests/` | Vendored Fleet engine and verification |

Instruction pages use this order when applicable:

1. Required outcome.
2. Preconditions and trust checks.
3. Ordered commands.
4. Verification.
5. Recovery or rollback.

Show a dry run before an apply. Keep its targets visible and under the current user home directory.

## Elevation & Depth

The repository has no visual elevation. Logical precedence supplies depth.

Rules compose from shared guidance to client guidance, then to a local host overlay. More specific layers may refine a shared rule.

Managed state also has a clear sequence:

1. Source files in the repository.
2. A validated plan from `bin/agents check` and `apply --dry-run`.
3. Backups of replaced files.
4. Links and generated client configuration.
5. Applied-state records used by status and rollback.

Do not hide this sequence behind a generic success message. Report the affected host, target, and state.

## Shapes

Paths and identifiers are the repository's structural shapes.

- Use lowercase kebab-case for skill directories.
- Use `SKILL.md` as the skill entry file.
- Use uppercase snake case for secret names.
- Use the documented host identifier in `hosts/<id>/` paths.
- Use repository-relative paths in portable guidance.
- Use tree diagrams only when hierarchy is easier to read than prose.

Do not add decorative icons, mascots, logos, border rules, or screenshots to explain a terminal-only operation.

## Components

### Wrapper and engine

`bin/agents` is the user-facing wrapper. `bin/fleet` and `lib/` implement validation, planning, apply, status, updates, and rollback.

Document wrapper commands unless a contributor must work on engine internals.

### Checks and plans

`bin/agents check` rejects unsafe public content. `bin/agents apply --dry-run --host <id>` exposes targets before writes.

Show the check and dry run beside every setup or recovery flow.

### Configuration

Keep Codex MCP data in TOML and Claude MCP data in JSON. Declare secret names separately in `mcp/required-secrets.txt`.

Preserve the schema and formatting of the file being edited. Do not invent a parallel configuration source.

### Host overlays

Local overlays hold machine paths, addresses, account names, and service details. Shared files describe the capability without embedding those values.

### Memory

Portable memory uses one Markdown fact per file and an index in `memory/MEMORY.md`. Follow `memory/README.md` for frontmatter and recall order.

### Command output

Print one labeled fact per line. Use deterministic JSON only when another program consumes the result.

Errors go to standard error and name the rejected condition. A failure must not print a success state.

## Do's and Don'ts

### Do

- Read the relevant README before changing a subsystem.
- Run `bin/agents check` and the related tests.
- Show dry-run targets before applying changes.
- Preserve backups and rollback behavior.
- Keep public and local-only data separate.
- Reuse existing paths, labels, and configuration schemas.
- Make commands safe to copy as written.

### Don't

- Do not commit secrets, host paths, private rules, or session data.
- Do not invent ANSI colors or graphical identity.
- Do not add a second source of truth for one setting.
- Do not hide destructive effects or skip confirmation.
- Do not claim a hosted URL or web interface.
- Do not use a host overlay to redefine shared behavior.
- Do not replace a recoverable operation with a destructive one.
