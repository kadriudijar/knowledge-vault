# knowledge-vault

This repo turns Obsidian vaults into Claude Code's knowledge base:

- **Notes vault:** at the start of a session, Claude loads the current project's note. Before it plans, it searches the vault for earlier work, and after real work it writes short notes.
- **Platform graph vault (optional):** a knowledge graph of services, Kafka topics, APIs, databases and business flows. Claude adds nodes and links when it confirms a connection in production code, and loads the current service's page at session start.

Each vault is committed and pushed after every turn. The code lives here; each vault is its own repo.

## Install

```bash
git clone https://github.com/kadriudijar/knowledge-vault ~/repos/knowledge-vault
git clone <your-notes-vault-repo> ~/notes-vault
git clone <your-platform-vault-repo> ~/platform-vault             # optional
npm install -g @tobilu/qmd                                        # optional hybrid search; ~2.1 GB of models on first query
~/repos/knowledge-vault/install.sh ~/notes-vault ~/platform-vault # leave out the second path to turn the platform vault off
```

Re-run `install.sh` in any of these cases:
- after anything overwrites `~/.claude/settings.json`
- after pulling changes to `hooks/`
- after changing the Node version

## What it installs

| Piece | Where | Does |
|---|---|---|
| `skills/knowledge-vault` | symlink in `~/.claude/skills` | Rules for searching, writing session notes, project notes, topic pages and answers, plus lint |
| `skills/platform-graph` | symlink in `~/.claude/skills`, with a platform vault | Rules for recording services, topics, APIs, databases and flows from production code |
| `hooks/session-start.sh` | copy in `~/.claude/hooks/knowledge-vault`, SessionStart | Loads the vault rules, the current project's note and, with a platform vault, the current service's page |
| `hooks/sync.sh` | copy in `~/.claude/hooks/knowledge-vault`, Stop | Commits, pulls and pushes each vault on its own, then refreshes the qmd index |
| settings | `~/.claude/settings.json` | Registers both hooks and gives Claude write access to the notes vault's `projects/` and `topics/` and the platform vault's node folders |
| graph colours | `<platform-vault>/.obsidian/graph.json` | Colours services, Kafka topics, APIs, databases and flows; keeps your own groups |
| qmd collections | `vault`, `platform` | Index the vaults' notes, if qmd is installed |

The hooks run as copies, not straight from this repo. They run without any permission check, so a `git pull` here changes nothing until you re-install.

## Vault layouts

```
<notes-vault>/
├── projects/<project>/<project>.md        project note: current state, loaded at session start
├── projects/<project>/YYYY-MM-DD-<slug>.md session notes and saved answers
├── topics/<topic>.md                      cross-project tools, systems and concepts
└── Knowledge.base                         Obsidian table of all notes

<platform-vault>/
├── services/<repo-name>.md                e.g. services/orders.md, loaded at session start
├── kafka/<topic-name>.md                  e.g. kafka/order-created.md
├── apis/<api-name>.md                     e.g. apis/shop.orders.Orders.md, apis/orders-rest.md
├── databases/<service>-db.md              e.g. databases/orders-db.md
└── flows/<flow-name>.md                   e.g. flows/checkout.md, with a Mermaid sequence diagram
```

The project (and service) name is the repo name from the `origin` remote, so second clones of a repo share one name. Without a remote, it is the main repo's folder name, and worktrees count as their main repo.

## Test

```bash
./hooks/test.sh
```
