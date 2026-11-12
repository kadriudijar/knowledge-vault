#!/bin/bash
# Self-check for session-start.sh and sync.sh against throwaway repos. Run: .claude/hooks/test.sh
set -e
HOOKS="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

# Vault clone with a bare remote, and a project note for "demo".
git init -q --bare "$T/remote.git"
g clone -q "$T/remote.git" "$T/vault" 2>/dev/null
mkdir -p "$T/vault/projects/demo" && echo "DEMO NOTE" > "$T/vault/projects/demo/demo.md"
g -C "$T/vault" add -A && g -C "$T/vault" commit -qm init && g -C "$T/vault" push -qu origin HEAD 2>/dev/null

# A repo named demo, a worktree of it, and a plain folder.
g init -q "$T/demo" && g -C "$T/demo" commit -q --allow-empty -m init
g -C "$T/demo" worktree add -q "$T/demo/.claude/worktrees/wt" 2>/dev/null
mkdir -p "$T/plain/sub"

start() { echo "{\"cwd\":\"$1\"}" | VAULT="$T/vault" "$HOOKS/session-start.sh"; }
start "$T/demo" | grep -q "Current project: demo" || fail "repo root"
start "$T/demo" | grep -q "DEMO NOTE" || fail "project note loaded"
out=$(start "$T/demo")
tag=$(echo "$out" | sed -n 's/^<\(project-note-[0-9]*\)>$/\1/p')
[ -n "$tag" ] && [ "$(echo "$out" | grep -c "^</$tag>$")" = 1 ] || fail "note wrapped in one random marker"
[ "$tag" != "$(start "$T/demo" | sed -n 's/^<\(project-note-[0-9]*\)>$/\1/p')" ] || fail "marker changes per session"
start "$T/demo/.claude/worktrees/wt" | grep -q "Current project: demo" || fail "worktree resolves to main repo"
start "$T/plain/sub" | grep -q "Current project: sub" || fail "non-repo folder"
start "$T/plain/sub" | grep -q "No project note yet" || fail "missing note message"

# The service name comes from the origin remote, so a second clone maps to the same name.
g clone -q "$T/remote.git" "$T/demo-copy" 2>/dev/null; g -C "$T/demo-copy" remote set-url origin git@example.com:org/demo.git
start "$T/demo-copy" | grep -qx "Current project: demo" || fail "ssh remote name"
g -C "$T/demo-copy" remote set-url origin https://example.com/org/demo
start "$T/demo-copy" | grep -qx "Current project: demo" || fail "https remote without .git"
g -C "$T/demo-copy" remote set-url origin https://example.com/org/demo/
start "$T/demo-copy" | grep -qx "Current project: demo" || fail "remote with trailing slash"
g -C "$T/demo-copy" remote set-url origin https://example.com/org/demo.git/
start "$T/demo-copy" | grep -qx "Current project: demo" || fail "remote with .git/"

# Platform vault: pointer line whenever it is set, service page in its own marked block.
mkdir -p "$T/platform/services" && echo "DEMO SERVICE" > "$T/platform/services/demo.md"
pstart() { echo "{\"cwd\":\"$1\"}" | VAULT="$T/vault" PLATFORM_VAULT="$T/platform" "$HOOKS/session-start.sh"; }
start "$T/demo" | grep -q "Platform graph vault" && fail "no platform line without PLATFORM_VAULT"
pstart "$T/plain/sub" | grep -q "Platform graph vault: $T/platform" || fail "platform pointer always shown"
pstart "$T/plain/sub" | grep -q "service-page-" && fail "no service block without a page"
pstart "$T/plain/sub" >/dev/null || fail "hook exits 0 without a service page"
out=$(pstart "$T/demo"); echo "$out" | grep -q "DEMO SERVICE" || fail "service page loaded"
st=$(echo "$out" | sed -n 's/^<\(service-page-[0-9]*\)>$/\1/p')
[ -n "$st" ] && [ "$(echo "$out" | grep -c "^</$st>$")" = 1 ] && [ "$(echo "$out" | grep -c "^</project-note-")" = 1 ] || fail "two blocks, distinct markers"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
wait_for() { for _ in $(seq 1 20); do git -C "$1" log --oneline 2>/dev/null | grep -q "sync vault notes" && return 0; perl -e 'select(undef,undef,undef,0.3)'; done; return 1; }

# sync.sh syncs both vaults on their own: a failing notes push doesn't stop the platform push.
git init -q --bare "$T/premote.git"
g clone -q "$T/premote.git" "$T/platform-clone" 2>/dev/null
g -C "$T/platform-clone" commit -q --allow-empty -m init && g -C "$T/platform-clone" push -qu origin HEAD 2>/dev/null
echo "svc" > "$T/platform-clone/orders.md"; echo "note" > "$T/vault/projects/demo/2026-01-02-y.md"
g -C "$T/vault" remote set-url origin "$T/missing.git"
VAULT="$T/vault" PLATFORM_VAULT="$T/platform-clone" "$HOOKS/sync.sh"
wait_for "$T/premote.git" || fail "platform vault pushed although notes push failed"
[ -z "$(git -C "$T/vault" status --porcelain)" ] || fail "notes vault still committed locally"
g -C "$T/vault" remote set-url origin "$T/remote.git"

# sync.sh commits and pushes a new note.
echo "new" > "$T/vault/projects/demo/2026-01-01-x.md"
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t VAULT="$T/vault" "$HOOKS/sync.sh"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  git -C "$T/remote.git" log --oneline 2>/dev/null | grep -q "sync vault notes" && break
  perl -e 'select(undef,undef,undef,0.3)'
done
git -C "$T/remote.git" log --oneline | grep -q "sync vault notes" || fail "sync pushed"

# install.sh, sandboxed in a fake HOME without qmd on PATH.
P="$T/platform-clone"
mkdir -p "$T/home/.claude" "$P/.obsidian" && echo '{}' > "$T/home/.claude/settings.json"
echo '{"showArrow": true, "colorGroups": [{"query": "path:mine", "color": {"a": 1, "rgb": 1}}]}' > "$P/.obsidian/graph.json"
inst() { HOME="$T/home" PATH=/usr/bin:/bin "$HOOKS/../install.sh" "$@" >/dev/null; }
# sync.sh commits and pushes the whole repo, so a vault must be a repo's top folder with an upstream.
mkdir -p "$T/notrepo"
inst "$T/vault" "$T/notrepo" && fail "refuse a vault that is not a git repo"
inst "$T/vault" "$T/vault/projects" && fail "refuse a subfolder of a repo"
g init -q "$T/noupstream"
inst "$T/noupstream" && fail "refuse a vault without an upstream"
[ "$(cat "$T/home/.claude/settings.json")" = "{}" ] || fail "refused installs leave settings alone"
inst "$T/vault" "$P"; inst "$T/vault" "$P"
S="$T/home/.claude/settings.json"; G="$P/.obsidian/graph.json"
[ "$(jq '[.hooks.SessionStart[].hooks[].command | select(contains("PLATFORM_VAULT"))] | length' "$S")" = 1 ] || fail "one session hook with platform"
jq -e '.permissions.additionalDirectories | index("'"$P"'/kafka")' "$S" >/dev/null || fail "kafka grant"
jq -e '.showArrow == true and ([.colorGroups[].query] | index("path:mine")) and ([.colorGroups[] | select(.query=="path:kafka") | .color.rgb] == [15769648])' "$G" >/dev/null || fail "graph.json merged"
[ "$(jq '.colorGroups | length' "$G")" = 6 ] || fail "no duplicate groups on re-run"
[ -L "$T/home/.claude/skills/platform-graph" ] || fail "platform skill linked"
inst "$T/vault"
jq -e '[.hooks[][] | .hooks[].command | select(contains("PLATFORM_VAULT"))] | length == 0' "$S" >/dev/null || fail "platform off"
[ ! -e "$T/home/.claude/skills/platform-graph" ] && [ ! -L "$T/home/.claude/skills/platform-graph" ] || fail "platform skill unlinked"

echo "All checks passed"
