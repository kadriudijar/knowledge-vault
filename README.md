# knowledge-vault

This repo turns an Obsidian vault into Claude Code's knowledge base. At the start of a session, Claude loads the current project's note. Before it plans, it searches the vault for earlier work, and after real work it writes short notes. The vault is committed and pushed after every turn.

The code lives here. The notes live in a separate vault repo.

## Install

```bash
git clone https://github.com/kadriudijar/knowledge-vault ~/repos/knowledge-vault
git clone https://github.com/kadriudijar/obsidian ~/obisidian    # the vault (notes repo)
npm install -g @tobilu/qmd                                        # optional hybrid search; ~2.1 GB of models on first query
~/repos/knowledge-vault/install.sh ~/obisidian
```

Re-run `install.sh` in any of these cases:
- after anything overwrites `~/.claude/settings.json`
- after pulling changes to `hooks/`
- after changing the Node version

## What it installs

| Piece | Where | Does |
|---|---|---|
| `skills/knowledge-vault` | symlink in `~/.claude/skills` | Rules for searching, writing session notes, project notes, topic pages and answers, plus lint |
| `hooks/session-start.sh` | copy in `~/.claude/hooks/knowledge-vault`, SessionStart | Loads the vault rules and the current project's note |
| `hooks/sync.sh` | copy in `~/.claude/hooks/knowledge-vault`, Stop | Commits, pulls and pushes the vault, then refreshes the qmd index |
| settings | `~/.claude/settings.json` | Registers both hooks and gives Claude write access to the vault's `projects/` and `topics/` |
| qmd collection | `vault` | Indexes `projects/**/*.md` and `topics/**/*.md`, if qmd is installed |

The hooks run as copies, not straight from this repo. They run without any permission check, so a `git pull` here changes nothing until you re-install.

## Vault layout

```
<vault>/
├── projects/<project>/<project>.md        project note: current state, loaded at session start
├── projects/<project>/YYYY-MM-DD-<slug>.md session notes and saved answers
├── topics/<topic>.md                      cross-project tools, systems and concepts
└── Knowledge.base                         Obsidian table of all notes
```

The project is the main git repo's folder name. Worktrees count as their main repo.

## Test

```bash
./hooks/test.sh
```
