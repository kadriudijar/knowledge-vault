---
name: knowledge-vault
description: The user's Obsidian knowledge vault, which replaces claude-mem. Use at the start of real work (a change, fix, investigation or setup task) to search the vault for how something was done or decided before; after finishing real work to write a session note and update the project and topic pages; after answering a question that took real investigation, to save the answer; and when the user asks to lint or health-check the vault. Also use when the user asks what was done before, how something was done, or to remember, save or record something.
---

# Knowledge Vault

The vault keeps knowledge current instead of re-deriving it. It holds four kinds of notes:

- **Project notes** describe a project as it is now.
- **Topic pages** describe, as it is now, a tool, system or concept used across projects.
- **Session notes** are short, dated records of one piece of work.
- **Answers** are saved results of investigations.

Claude reuses these notes so it doesn't redo past work, and the user reads them in Obsidian to learn about their projects.

**Vault path:** given at session start as `Knowledge vault: <path>`. If that line is missing, take the `VAULT=` value from the knowledge-vault hook commands in `~/.claude/settings.json`.
**Current project:** given at session start as `Current project: <name>`. It is the main git repo's folder name.

## Search before planning real work

Keep searches small. Find candidates first, then open only the notes that matter.

1. List the project's notes: Grep pattern `^summary:` in `<vault>/projects/<project>`, output mode `content`, head_limit 20.
2. Search the whole vault for the task.
   - **With qmd** (`command -v qmd` succeeds):
     - `qmd query "<what you need, in plain words>" -c vault -n 5 --full-path` searches by meaning.
     - `qmd search "<exact names, commands or error text>" -c vault -n 5 --full-path` is a faster keyword search.
     - Both return paths with a score and a snippet. Ignore results scored under about 40%.
   - **Without qmd, or if it fails:** Grep in `<vault>` with glob `{projects,topics}/**/*.md`, output mode `files_with_matches`, head_limit 10. For tags, search `^tags:.*<tag>`. For notes that mention another project or topic, search `\[\[<name>\]\]`.
3. Read only the 1–3 notes that fit best. If a note has `superseded-by`, read the newer note instead. If the work involves a topic page, read that page too.
4. Before reusing a How section, check it against the current code and config. Notes are history; the code is the truth.

Skip searching for quick questions or one-off reads.

## Write after finishing real work

Write a note as soon as a task is finished, not at the end of the session; early details are lost when a long session is compacted. Write one when something changed, something was fixed, a decision was made, or a non-obvious lesson was learned. Don't write one for a quick question or a read with no outcome.

One write touches at most three notes: the session note or answer, the project note, and one topic page. Don't fan out across the vault.

Do not commit or push. The Stop hook commits and pushes the vault and refreshes the qmd index at the end of every turn.

### Session note

Path: `<vault>/projects/<project>/YYYY-MM-DD-<short-kebab-slug>.md`. Use a specific slug, because note names must be unique across the vault for `[[links]]` to resolve. Stay under about 40 lines.

```markdown
---
project: <project>
type: session
date: YYYY-MM-DD
tags: [lowercase, kebab-case, tools-and-topics]
summary: One specific line a later search will hit, e.g. "Seeded a test player on orbstack via UpsertProfile on upsert-profile"
---
Part of [[<project>]]. Topics: [[<topic>]]

## What
What was done and why, in 2–4 lines.

## How
The steps, commands, files and config that made it work, so it can be repeated.

## Decisions
- Decision — why, and what was rejected.

## Next time
Gotchas, dead ends, and what is still open.
```

Leave out sections that would be empty, and leave out the Topics part if there is no topic page. Link related work with `[[note-name]]` and other projects with `[[<other-project>]]`.

### Project note

Path: `<vault>/projects/<project>/<project>.md`. Create it with the project's first session note. It is loaded into every session in this project, so keep it under about 150 lines. Rewrite it in place so it always describes the current state, never append a changelog.

```markdown
---
project: <project>
type: project
updated: YYYY-MM-DD
summary: One line on what this project is
---
## What it is
## How it's built
Architecture, key folders and files, integrations, how to run and test.
## Key decisions
- Decision — why. ([[YYYY-MM-DD-slug]])
## How to
- Task — [[YYYY-MM-DD-slug]]
```

Update it when the project's purpose, structure, decisions or recipes change. When a new session note replaces an older note's How section or decision, add `superseded-by: "[[new-note]]"` to the older note's properties and update the project note's links.

### Topic page

Path: `<vault>/topics/<topic>.md`, named in kebab-case, for example `orbstack-cluster` or `kafka-debezium`. A topic is a tool, system or concept that more than one project uses. Create the page when the topic turns up in a second project, or when the user asks for it, not before. Like a project note, it describes the current state and is rewritten in place. Keep it under about 100 lines.

```markdown
---
topic: <topic>
type: topic
updated: YYYY-MM-DD
tags: [lowercase, kebab-case]
summary: One line on what this is and what it is used for
---
## What it is
## How we use it
- [[<project>]] — how this project uses it.
## Gotchas
## How to
- Task — [[YYYY-MM-DD-slug]]
```

Session notes and answers that involve the topic link to `[[<topic>]]`. When a session teaches something new about a topic, update the topic page as that session's one topic write.

### Answer

Save an answer when a question took real investigation, such as reading several files, running commands or comparing sources, and the result is worth finding again. Also save one whenever the user says "save this". Don't save quick lookups.

Path: `<vault>/projects/<project>/YYYY-MM-DD-<short-kebab-slug>.md`, in the project the session runs in, even when the question spans several projects; link those projects and topics. If the answer changes what a project note or topic page says, update that page too.

```markdown
---
project: <project>
type: answer
date: YYYY-MM-DD
tags: [lowercase, kebab-case]
summary: The answer in one line
---
Part of [[<project>]]. Topics: [[<topic>]]

## Question
## Answer
## Sources
The files, commands and notes the answer is based on, so it can be checked again.
```

## Lint (when the user asks to lint or health-check the vault)

Check the items below in order. Report findings as a short list grouped by check. Fix mechanical problems (missing properties, broken links, missing `superseded-by`) directly. Ask before deleting a note or rewriting what it says.

1. **Secrets, first.** Grep `<vault>/projects` and `<vault>/topics` case-insensitively for each of these:
   - `(password|passwd|secret|token|api[_-]?key|client[_-]?secret|connection ?string)\s*[:=]\s*\S`
   - `-----BEGIN [A-Z ]*PRIVATE KEY-----`
   - `ghp_[A-Za-z0-9]{20,}`
   - `github_pat_`
   - `sk-[A-Za-z0-9-]{20,}`
   - `AKIA[0-9A-Z]{16}`
   - `xox[abprs]-`
   - `eyJ[A-Za-z0-9_-]{10,}\.eyJ`
   - `://[^/\s:]+:[^@\s]+@`, which catches credentials in URLs

   Remove any real value right away. Then tell the user it is still in the git history on GitHub and must be rotated.
2. **Properties.** Every note has `project` (or `topic`), `type`, `summary`, and `date` (or `updated`).
3. **Size.** Flag project notes over about 150 lines, topic pages over about 100, and session notes or answers over about 60.
4. **Broken links.** Flag any `[[name]]` with no `name.md` anywhere in the vault.
5. **Drift.** Flag decisions or How sections in project and topic pages that newer session notes contradict, and older notes that newer ones replaced but that have no `superseded-by`.
6. **Missing topics.** Flag tags or `[[links]]` that appear in notes from two or more projects but have no topic page, and topic pages that nothing links to.

## Never write

Secrets, passwords, tokens, API keys, private keys, connection strings, or personal data of customers or players. Record where a secret lives (for example "the `wallets-db` secret in the `apps` namespace"), never its value. The vault is pushed to GitHub.
