# Memory

Durable, portable memory for my agent CLIs. Plain Markdown, one fact per file, indexed in
`MEMORY.md`, versioned in Git. No server, no database — greppable and diffable, so it
survives a machine reset and travels with the rest of this repo.

## Why files, not a vector server

Systems like [supermemory](https://github.com/supermemoryai/supermemory) run an embedding
or graph backend with hybrid RAG retrieval. That is powerful, but it needs a running
service and is hard to audit. This store keeps the good ideas — fact extraction, a typed
ontology, project scoping, and temporal awareness — in flat files that any agent can read
and any human can review in a diff.

## One fact per file

Each memory is one `.md` file. Frontmatter drives recall:

```markdown
---
name: <short-kebab-case-slug>
description: <one line, used to judge relevance during recall>
metadata:
  type: user | feedback | project | reference
  updated: YYYY-MM-DD
---

<the fact. For feedback/project, add **Why:** and **How to apply:** lines.>
<Link related memories with [[their-name]].>
```

## Types

- **user** — who I am: role, expertise, standing preferences.
- **feedback** — how I want agents to work; corrections and confirmed approaches. Include the why.
- **project** — ongoing work, goals, constraints not derivable from code or Git history. Use absolute dates.
- **reference** — pointers to external resources (URLs, dashboards, tickets, tools).

## Recall — 3-layer, filter before fetch

1. **Index (free).** `MEMORY.md` is already loaded. Filter one-liners to candidate slugs. If a one-liner answers it, stop.
2. **Locate (cheap).** Still unsure? `grep -rniE '<keyword>' memory/` returns filenames and matching lines, not full bodies. Narrow to at most 3 slugs.
3. **Fetch (last).** Read only the winning files in full.

Do not read a memory file until layers 1–2 narrow to 3 candidates or fewer.

## Temporal awareness

Stamp `updated:` in frontmatter. When a fact changes, update the file; when it is proven
wrong, delete it. When a newer fact supersedes an older one, say so and link
`[[old-name]]`. Convert relative dates ("last week") to absolute dates before saving.

## Boundary

Personal content only. Keep work or client facts in a separate work store.
No secrets, tokens, or credentials (see the repo `.gitignore`).

## Adding a memory

1. Write the `.md` file with frontmatter.
2. Add a one-line pointer to `MEMORY.md`: `- [Title](file.md) — hook`.
3. Keep the one-liner dense enough that layer 1 alone often answers.
