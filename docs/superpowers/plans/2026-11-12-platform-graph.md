# Platform Graph Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second Obsidian vault, a platform knowledge graph, that Claude grows from production code while it works. Claude loads the current service's page at session start and syncs the vault after every turn.

**Architecture:** Extend the existing hooks and installer in this repo instead of adding new ones. `session-start.sh` and `sync.sh` take an optional `PLATFORM_VAULT`, and `install.sh` takes an optional second argument. A new skill, `skills/platform-graph/SKILL.md`, holds the recording rules. The vault itself is a separate private git repo.

**Tech Stack:** bash, git, jq, python3 (stdlib) in `install.sh`, qmd CLI (optional), Obsidian.

**Spec:** `docs/superpowers/specs/2026-11-12-platform-graph-design.md`

## Global Constraints

- The repo is public. No real platform service, topic, API or secret names appear in code, skills, README, spec or plan. Examples use `orders`, `payments`, `order-created`, `shop.orders.Orders`.
- Node folders are `services/`, `kafka/`, `apis/`, `databases/` and `flows/`. Never use `topics/`.
- Colour groups are `{"query": "path:<folder>", "color": {"a": 1, "rgb": <int>}}`, with these values: services 5214967, kafka 15769648, apis 11566832, databases 8947848, flows 4174719.
- Links go only in note bodies. Properties hold no links.
- The service name is the last path segment of `git remote get-url origin` without `.git`, so it handles both `https://host/org/repo.git` and `git@host:org/repo.git`. Otherwise it falls back to the existing folder logic.
- Each vault syncs independently. One vault's failure never stops the other.
- Hook output for each note uses its own random marker and a 20000-byte cap.
- Commit messages use `feat:`, `fix:` or `chore:` with no AI attribution. Squash the branch to one commit before pushing.

## Review Focus

1. **Remote URL shapes** (ssh `git@host:org/repo.git`, https with or without `.git`) all give `repo`. Test: Task 1.
2. **Re-running the installer with only the notes vault** turns the platform off: no `PLATFORM_VAULT` in hooks and no `platform-graph` link. Test: Task 3.
3. **An existing `.obsidian/graph.json`** with the user's own settings and colour groups keeps them after install. Our five groups are added or updated by query. Test: Task 3.
4. **A notes vault push that fails** (bad remote) still lets the platform vault push. Test: Task 2.
5. **Two notes loaded in one session** (project note plus service page) each get a distinct marker, closed exactly once. Test: Task 1.

---

### Task 1: Session start — remote-based name, platform pointer, service page

**Files:**
- Modify: `hooks/session-start.sh`
- Test: `hooks/test.sh`

**Interfaces:**
- Consumes: env `VAULT` (required), `PLATFORM_VAULT` (optional), stdin JSON `{"cwd": ...}`.
- Produces: output lines `Current project: <name>`, `Platform graph vault: <path> ...` (only when `PLATFORM_VAULT` is set), and data blocks `<project-note-N>…</project-note-N>` and `<service-page-N>…</service-page-N>`. Task 5 relies on the `Platform graph vault:` line.

- [ ] **Step 1: Add failing tests to `hooks/test.sh`** (after the existing session-start checks; add a `$T/platform` dir with `services/demo.md` containing `DEMO SERVICE`):

```bash
g clone -q "$T/remote.git" "$T/demo-copy" 2>/dev/null; g -C "$T/demo-copy" remote set-url origin git@example.com:org/demo.git
start "$T/demo-copy" | grep -q "Current project: demo" || fail "ssh remote name"
g -C "$T/demo-copy" remote set-url origin https://example.com/org/demo
start "$T/demo-copy" | grep -q "Current project: demo" || fail "https remote without .git"
pstart() { echo "{\"cwd\":\"$1\"}" | VAULT="$T/vault" PLATFORM_VAULT="$T/platform" "$HOOKS/session-start.sh"; }
start "$T/demo" | grep -q "Platform graph vault" && fail "no platform line without PLATFORM_VAULT"
pstart "$T/plain/sub" | grep -q "Platform graph vault: $T/platform" || fail "platform pointer always shown"
pstart "$T/plain/sub" | grep -q "service-page-" && fail "no service block without a page"
out=$(pstart "$T/demo"); echo "$out" | grep -q "DEMO SERVICE" || fail "service page loaded"
st=$(echo "$out" | sed -n 's/^<\(service-page-[0-9]*\)>$/\1/p')
[ -n "$st" ] && [ "$(echo "$out" | grep -c "^</$st>$")" = 1 ] && [ "$(echo "$out" | grep -c "^</project-note-")" = 1 ] || fail "two blocks, distinct markers"
```

- [ ] **Step 2: Run `hooks/test.sh`.** Expected: `FAIL: ssh remote name`.
- [ ] **Step 3: Implement in `hooks/session-start.sh`:**
  - Name: `name=${remote##*[/:]}; name=${name%.git}` when `origin` exists, otherwise the current folder logic.
  - Add `print_block <tag-prefix> <label> <file>`, which prints the label line, then `<prefix-$RANDOM$RANDOM$RANDOM>`, `head -c 20000`, a newline and the closing tag. Use it for the project note and the service page.
  - When `PLATFORM_VAULT` is set:
    - background-pull the platform vault the same way as the notes vault
    - print `Platform graph vault: $PLATFORM_VAULT. When work shows how services connect, record it with the platform-graph skill; before changing how a service talks to others, read its page and its neighbours.`
    - print the unpushed-commits warning naming the platform vault
    - `print_block service-page "Service page (…)" "$PLATFORM_VAULT/services/$project.md"` if that file exists
  - The unpushed warning names its vault (`notes vault` or `platform vault`).
- [ ] **Step 4: Run `hooks/test.sh`.** Expected: `All checks passed`.
- [ ] **Step 5: Commit** `feat: load the platform service page at session start`.

### Task 2: Sync both vaults independently

**Files:**
- Modify: `hooks/sync.sh`
- Test: `hooks/test.sh`

**Interfaces:**
- Consumes: env `VAULT` (required), `PLATFORM_VAULT` (optional).
- Produces: no output. It commits `chore: sync vault notes` in each vault that has changes, pushes each one, then runs `qmd update && qmd embed` once.

- [ ] **Step 1: Add failing tests.** Create a second bare remote, `$T/premote.git`, and a clone, `$T/platform-clone`, with a first commit pushed upstream. Write one file in each vault. Point the notes vault's `origin` at `$T/missing.git` so its push fails. Run `sync.sh` with both env vars, then poll as the existing test does:

```bash
git -C "$T/premote.git" log --oneline | grep -q "sync vault notes" || fail "platform vault pushed although notes push failed"
[ -z "$(git -C "$T/vault" status --porcelain)" ] || fail "notes vault still committed locally"
```

  Restore the notes vault `origin` afterwards, then keep the existing single-vault test.
- [ ] **Step 2: Run `hooks/test.sh`.** Expected: `FAIL: platform vault pushed…`.
- [ ] **Step 3: Implement** `sync_one <vault-dir>` in `hooks/sync.sh`, containing the current add/commit/pull/push body. Run it in a subshell for `"$VAULT"`, and for `"$PLATFORM_VAULT"` when set, then run qmd once. Everything stays inside the single background block.
- [ ] **Step 4: Run `hooks/test.sh`.** Expected: `All checks passed`.
- [ ] **Step 5: Commit** `feat: sync the platform vault alongside the notes vault`.

### Task 3: Installer — optional platform vault

**Files:**
- Modify: `install.sh`
- Test: `hooks/test.sh` (installer section, sandboxed with `HOME="$T/home"` and a `PATH` without qmd: `PATH=/usr/bin:/bin`)

**Interfaces:**
- Consumes: `install.sh <notes-vault> [<platform-vault>]`.
- Produces:
  - hook commands `VAULT="…" [PLATFORM_VAULT="…"] [PATH="…:$PATH"] "<hooks>/<script>"`
  - link `~/.claude/skills/platform-graph`, created when the platform argument is given and removed otherwise
  - folders `services kafka apis databases flows` in the platform vault
  - `.obsidian/graph.json` with the five groups
  - `additionalDirectories` entries for each node folder
  - qmd collection `platform`, with mask `services/**/*.md,kafka/**/*.md,apis/**/*.md,databases/**/*.md,flows/**/*.md`

- [ ] **Step 1: Add failing tests.** Seed `$T/home/.claude/settings.json` with `{}`. Seed `$T/platform/.obsidian/graph.json` with `{"showArrow": true, "colorGroups": [{"query": "path:mine", "color": {"a": 1, "rgb": 1}}]}`. Run `install.sh "$T/vault" "$T/platform"` twice, then check:

```bash
S="$T/home/.claude/settings.json"
[ "$(jq '[.hooks.SessionStart[].hooks[].command | select(contains("PLATFORM_VAULT"))] | length' "$S")" = 1 ] || fail "one session hook with platform"
jq -e '.permissions.additionalDirectories | index("'"$T/platform"'/kafka")' "$S" >/dev/null || fail "kafka grant"
G="$T/platform/.obsidian/graph.json"
jq -e '.showArrow == true and ([.colorGroups[].query] | index("path:mine")) and ([.colorGroups[] | select(.query=="path:kafka") | .color.rgb] == [15769648])' "$G" >/dev/null || fail "graph.json merged"
[ "$(jq '.colorGroups | length' "$G")" = 6 ] || fail "no duplicate groups on re-run"
[ -L "$T/home/.claude/skills/platform-graph" ] || fail "platform skill linked"
```

  Then run `install.sh "$T/vault"` with only the notes vault, and check:

```bash
jq -e '[.hooks[][] | .hooks[].command | select(contains("PLATFORM_VAULT"))] | length == 0' "$S" >/dev/null || fail "platform off"
[ ! -e "$T/home/.claude/skills/platform-graph" ] || fail "platform skill unlinked"
```

- [ ] **Step 2: Run `hooks/test.sh`.** Expected: `FAIL: one session hook with platform`.
- [ ] **Step 3: Implement in `install.sh`:**
  - Parse an optional `$2` (it must be a directory) into `PLATFORM`.
  - Link or remove `platform-graph`.
  - Create the node folders.
  - Pass `PLATFORM` into the python block, which:
    - adds `PLATFORM_VAULT="…"` to both commands
    - adds the five grants
    - merges `graph.json` by `query`: replace ours, keep others and all other keys
  - Register the qmd collection with the same `grep … >/dev/null ||` pattern used for `vault`.
  - Update the usage line and the closing echo.
- [ ] **Step 4: Run `hooks/test.sh`.** Expected: `All checks passed`.
- [ ] **Step 5: Commit** `feat: install the optional platform vault`.

### Task 4: Skills and README

**Files:**
- Create: `skills/platform-graph/SKILL.md`
- Modify: `skills/knowledge-vault/SKILL.md:54,97,163`, `README.md`

**Interfaces:**
- Consumes: the `Platform graph vault:` line (Task 1), the folders and colours (Global Constraints).
- Produces: the skill `platform-graph`, whose description triggers on "reading code that shows how services connect (gRPC, REST, Kafka, database, CDC), or when the user asks how services interact".

- [ ] **Step 1: Write `skills/platform-graph/SKILL.md` from the spec.** Use the spec's sections "Page format", "Vault layout" naming rules, "Recording" steps 1–7, "Search", and calls 6, 8 and 9. List the code signals:
  - gRPC client and server registration
  - Kafka producer and consumer config
  - REST client base address
  - DbContext or grain storage
  - CDC connector config

  Rejected evidence paths: `test`, `tests`, `*Tests*`, `spec`, `fixtures`, `samples`. Include one invented example page per type, using `orders` and `order-created`.
- [ ] **Step 2: Replace the real names in `skills/knowledge-vault/SKILL.md`:**
  - line 54: `"Seeded a test order in the local cluster via CreateOrder on order-requests"`
  - line 97: `` `local-cluster` or `kafka-cdc` ``
  - line 163: `` "the `orders-db` secret in the `apps` namespace" ``
- [ ] **Step 3: Update `README.md`:** add the optional second argument, the second clone line, and the `platform-graph` row in the "What it installs" table.
- [ ] **Step 4: Verify that no real names remain.** Grep `skills README.md install.sh hooks docs` for the real names from the old examples and for the user's platform service, topic and namespace names. Keep the pattern in a scratch file outside the repo, never in a tracked file. Expected: no matches.
- [ ] **Step 5: Commit** `feat: add the platform-graph skill and scrub real names from examples`.

### Task 5: Create the vault, install, and run live checks

**Files:**
- Create: `/Users/mac/platform-vault/` with `.gitignore` (copied from `/Users/mac/obisidian/.gitignore`) and `.gitkeep` in each node folder.

- [ ] **Step 1:** Run `git init -b main`, add the files, commit `feat: start the platform graph vault`, then run `gh repo create kadriudijar/platform-vault --private --source . --push`. Expected: `gh repo view kadriudijar/platform-vault --json visibility -q .visibility` prints `PRIVATE`.
- [ ] **Step 2:** Run `./install.sh /Users/mac/obisidian /Users/mac/platform-vault`, then run `hooks/test.sh`. Expected: both hook commands contain `PLATFORM_VAULT="/Users/mac/platform-vault"`, `platform-vault/.obsidian/graph.json` has 5 groups, and `qmd collection list` shows `platform`.
- [ ] **Step 3: Live record check.** Pick one service repo under `/Users/mac/repos` at run time. In it, run `claude -p "<ask it to find and record one connection this service has, confirmed in production code>" --model sonnet` with `Skill`, `Read`, `Grep`, `Glob`, `Bash(git:*)`, `Bash(qmd:*)`, `Write` and `Edit` allowed. Expected:
  - a new page under `services/` and at least one under `kafka/`, `apis/` or `databases/`
  - `sources:` paths without test folders
  - `[[` links only in the body
  - a `chore: sync vault notes` commit on `origin/main` of the platform vault
- [ ] **Step 4: Live refusal check.** In the same repo, find a call that only a test file makes, then ask Claude to record it as a connection, citing only that test file. Expected: the reply refuses, and the platform vault gains no link for it.
- [ ] **Step 5:** Ask the user to open `/Users/mac/platform-vault` in Obsidian once and confirm the colours in the graph view. Record the result.

### Task 6: Notes, squash, push, review

- [ ] **Step 1:** Update the notes vault project note `projects/knowledge-vault/knowledge-vault.md` (second vault, installer argument, name rule). Write the session note `2026-11-12-platform-graph-vault.md`.
- [ ] **Step 2:** Squash the branch into one commit, `feat: add the platform graph vault`, then push `feat/platform-graph`.
- [ ] **Step 3:** Run a whole-branch review with a fresh reviewer on the most capable model. Fold any fixes into the one commit with `--amend`, and push with `--force-with-lease` to the feature branch only.
- [ ] **Step 4:** Ask the user whether to merge into `main` (fast-forward) or open a PR.
