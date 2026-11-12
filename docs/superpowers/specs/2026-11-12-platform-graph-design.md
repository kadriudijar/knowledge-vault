# Platform graph vault — design

## Intent

The user wants a knowledge graph of how their platform works and how its parts interact. It covers services, Kafka topics, APIs, databases and business flows. It grows while the user works with Claude: when Claude confirms a connection in a service's code, it records it. The user explores the result in Obsidian's graph view. Claude loads the current service's page at session start and searches the vault before it plans.

This is a second vault next to the existing notes vault. The notes vault records *what we did*. The platform vault records *how the platform is built*.

## Decided by the user

- The graph is the main view.
- The graph shows full detail: services, Kafka topics, APIs, databases and flows, each as its own node.
- The vault starts empty and grows as we work. It is not seeded from `knowledge-engineering`.
- A separate vault is acceptable.

## Goals

- **Graph:** Obsidian's graph view shows five node types in five colours.
- **Docs:** each node has a short page that says what it is and what it connects to.
- **Diagrams:** each flow page has a Mermaid sequence diagram, which Obsidian renders.
- Every connection is traceable to a source file in a service repo.
- Claude commits and pushes the vault to its own private GitHub repo after every turn, as it does for the notes vault.

## Non-goals

- No bulk import, analyzer or seeding. The graph only grows from real work.
- No Canvas platform map (mockup option D).
- No labels on graph lines. Obsidian cannot draw them. The intermediate node (topic, API, database) shows how two services connect.
- No replacement for the organisation's developer portal docs. This vault is a personal view derived from code.
- No lint for this vault in this change.

## Anti-goals

- **Wrong connections.** A connection seen only in tests, samples or fixtures is never recorded. A wrong edge is worse than a missing edge.
- **Secrets or real data values** in any page.
- **A hairball.** Only record nodes that carry a real connection. No pages for libraries, helpers or internal classes.
- **Breaking the notes vault.** The notes vault keeps working when the platform vault is not installed.

## Constraints

- The code repo `kadriudijar/knowledge-vault` is **public**. Code, skill text, README and this spec use invented examples (`orders`, `payments`, `order-created`). They never name real platform services, topics or APIs.
- Obsidian draws a graph line for each link in the note **body**. Pages put every link in the body. Property values hold no links.
- Hooks run as copies in `~/.claude/hooks/knowledge-vault/`. A change takes effect after `install.sh` runs again.
- `.obsidian/` is outside Claude's write grant. The installer writes the graph config.
- Obsidian stores graph colour groups in `.obsidian/graph.json` as `colorGroups: [{ "query": "<search>", "color": { "a": 1, "rgb": <int> } }]`. This is confirmed from Obsidian's own code (`getColoredQueries`).

## My calls (the user should check these)

1. **Location:** the vault is at `/Users/mac/platform-vault`, with a new private GitHub repo `kadriudijar/platform-vault`. It is auto-committed and pushed like the notes vault.
2. **Session start** loads the current service's page as well as the notes project note.
3. **Evidence:** only production code counts. Paths under test, sample or fixture folders are rejected.
4. **Code:** a second skill, `platform-graph`, goes in the `knowledge-vault` repo. It uses the same hooks and the same installer.
5. **Service identity** is the repo name from `git remote get-url origin`. The folder name is the fallback when there is no remote. Second clones (a folder named `orders-feature` with the `orders` remote) map to one service. The notes vault's project name changes to the same rule. No existing notes folder is a clone name, so no notes move.
6. **Neighbours:** when a service connects to a service nobody has worked in yet, Claude creates a stub page for the neighbour with `status: stub`. The stub's facts come from the side Claude has read.
7. **Both sides link.** A service page links the topics it produces, and the topic page links that service back. Graph arrows stay off, because two-way links would make every arrow double. Direction is in the page sections.
8. **What counts as a service:** one repo is one service page. A repo with several deployables (for example a host and a worker) still gets one page, with a section per deployable. Libraries, chart repos, environment repos and tooling repos never get a service page. Their production config (for example a CDC connector or Helm values) is still valid evidence for the services it configures.
9. **Stub to verified:** a stub becomes `verified` when a session in that service's own repo confirms it from its own code. That session rewrites the page from its code, replaces the stub's facts where they differ, and adds its own `sources`.
10. **Sync isolation:** each vault syncs on its own. A failure in one never blocks the other. On a pull conflict, both use the existing rule: abort, keep the local commits, and warn at session start. The warning names the vault.
11. **Installer arguments:** each `install.sh` run rebuilds the hook commands from its arguments. Running it with only the notes vault turns the platform vault off: no `PLATFORM_VAULT` in the hooks and no `platform-graph` skill link. Old write grants and the old qmd collection stay; they are harmless.
12. **Side effects are build steps:** the builder creates the platform vault folder and the private GitHub repo, runs `install.sh` against the real `~/.claude/settings.json`, and runs the live `claude -p` checks. These are not hand-off steps for the user.
13. **Public examples:** the existing public `skills/knowledge-vault/SKILL.md` names real platform topics and a real secret location in its examples. This change replaces them with invented examples. The old text stays in the public git history.
14. **Name rule fallback:** a repo with no `origin` uses its folder name. If it gets an `origin` with a different name later, its notes and its service page start under the new name. This is documented, and nothing migrates automatically.

## Vault layout

```
platform-vault/
├── services/<repo-name>.md          e.g. services/orders.md
├── kafka/<topic-name>.md            verbatim topic name, e.g. kafka/order-created.md
├── apis/<api-name>.md               gRPC: full service name (shop.orders.Orders.md); REST: <service>-rest.md
├── databases/<service>-db.md        e.g. databases/orders-db.md
├── flows/<flow-name>.md             kebab-case business name, e.g. flows/checkout.md
└── .obsidian/graph.json             colour groups, written by the installer
```

The folder is `kafka/`, not `topics/`. In the notes vault, `topics/` means cross-project concept pages.

Wikilinks resolve by file name across the whole vault, so names must be unique. The suffixes `-db` and `-rest` and the full gRPC name keep the node types apart. If a name still clashes, append the type, for example `checkout-flow`.

Colour groups:

| Query | Colour | rgb int |
|---|---|---|
| `path:services` | blue `#4F8EF7` | 5214967 |
| `path:kafka` | orange `#F0A030` | 15769648 |
| `path:apis` | purple `#B07EF0` | 11566832 |
| `path:databases` | grey `#888888` | 8947848 |
| `path:flows` | green `#3FB37F` | 4174719 |

## Page format

Every page has these properties, with no links in them:

```yaml
type: service | kafka-topic | api | database | flow
summary: One line on what this is
status: verified | stub
updated: YYYY-MM-DD
sources:                       # plain text, production code only
  - orders:src/Orders.Host/Kafka/OrderCreatedProducer.cs:42
```

The body sections hold the links. Leave out empty sections.

- **Service:** What it does · Exposes (APIs) · Calls (APIs of other services, with why) · Produces (topics) · Consumes (topics) · Owns (databases) · Reads (other services' databases, for example through CDC) · Flows · Gotchas.
- **Kafka topic:** Produced by · Consumed by · Message (shape in a few lines) · Flows.
- **API:** Kind (gRPC or REST) · Served by · Methods (names only) · Called by.
- **Database:** Owned by · Engine · Main tables or state · Read by.
- **Flow:** Steps (a numbered list with links) · a Mermaid `sequenceDiagram` · Services involved.

Size: node pages stay under about 40 lines, and flow pages under about 80.

## Behaviour

### Session start

When `PLATFORM_VAULT` is set, the SessionStart hook always prints one line with the platform vault path and a pointer to the `platform-graph` skill. Without that line, an empty vault could never start to grow. The hook works out the service name (see call 5). If `<platform-vault>/services/<name>.md` exists, the hook also prints it in its own data block. That block has its own random marker and a byte cap, the same as the project note. The hook cannot tell whether a repo is a service. The skill decides that (call 8).

### Recording (the `platform-graph` skill)

The trigger is any time during work when Claude reads code that shows a connection. Examples are a gRPC client or server registration, a Kafka producer or consumer, a REST client base address, a DbContext or grain storage, or a CDC connector config. At the end of that task, Claude then does the following:

1. Search the vault first and update existing pages instead of creating duplicates.
2. Record only what production code shows, and add each file to `sources`.
3. Touch at most 6 pages per task.
4. Create a stub for any neighbour that has no page (call 6).
5. Create or update a flow page only when a business flow was traced end to end, or when the user asks for it.
6. When code shows that a connection is gone, remove the link and record the source.
7. Never write secrets, connection strings, hostnames with credentials, or real data values.

### Search

qmd gets a second collection, `platform`, over `services`, `kafka`, `apis`, `databases` and `flows`. Grep is the fallback. Before planning work that changes how a service talks to others, Claude reads the service's page and its direct neighbours.

### Sync

The Stop hook commits and pushes both vaults, then refreshes qmd once.

## Code changes (touch list)

- `skills/platform-graph/SKILL.md` — new skill (recording, search, page formats, naming).
- `hooks/session-start.sh` — service name from the git remote; load the platform service page in its own marked and capped block when `PLATFORM_VAULT` is set; the notes project uses the same name rule.
- `hooks/sync.sh` — sync `VAULT` and, if set, `PLATFORM_VAULT`; run `qmd update && qmd embed` once at the end.
- `install.sh` — `install.sh <notes-vault> [<platform-vault>]`:
  - pass `PLATFORM_VAULT` to both hook commands
  - grant write access to the five node folders
  - create the folders
  - register the qmd collection `platform` (the existing check only looks for `^vault `)
  - write the colour groups into `.obsidian/graph.json`, merging with any existing file
  - link the second skill
- `hooks/test.sh` — the platform page loads in its own marked block; a second clone resolves to the remote name; sync handles two vaults.
- `README.md` — the second vault and the new installer argument.
- `skills/knowledge-vault/SKILL.md` — replace the real names in the examples with invented ones (call 13).
- Platform vault repo — `git init`, `.gitignore` (same as the notes vault), `.gitkeep` per folder, initial commit, `gh repo create kadriudijar/platform-vault --private --push`.

Work happens on branch `feat/platform-graph`. Public `main` is not amended again.

## Verification

1. `hooks/test.sh` passes with the new assertions.
2. In a fresh `claude -p` session in one real service repo, ask Claude to record one connection it confirms in code. The check passes when:
   - the page is in the right folder
   - `sources` names a non-test path
   - the links are in the body
   - the commit reaches `kadriudijar/platform-vault`
3. In the same kind of session, ask Claude to record a connection that only a test shows. The check passes when Claude refuses.
4. The user opens `/Users/mac/platform-vault` in Obsidian once, by hand, and confirms the colours in the graph view. This step cannot be automated.

## Left to the builder

- The exact skill wording and the list of code signals per language.
- Byte caps and the 6-page limit, if testing shows better numbers.
- How `install.sh` merges into an existing `graph.json`.
