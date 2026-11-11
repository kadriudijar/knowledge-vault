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

# sync.sh commits and pushes a new note.
echo "new" > "$T/vault/projects/demo/2026-01-01-x.md"
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t VAULT="$T/vault" "$HOOKS/sync.sh"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  git -C "$T/remote.git" log --oneline 2>/dev/null | grep -q "sync vault notes" && break
  perl -e 'select(undef,undef,undef,0.3)'
done
git -C "$T/remote.git" log --oneline | grep -q "sync vault notes" || fail "sync pushed"

echo "All checks passed"
