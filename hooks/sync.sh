#!/bin/bash
# Stop hook: commits any vault changes (Claude's notes and your Obsidian edits) and pushes them, in the background.
: "${VAULT:?VAULT must be set; install.sh puts it in the hook command}"
cd "$VAULT" || exit 0

{
  git add -A
  git diff --cached --quiet || git commit -qm "chore: sync vault notes"
  if [ "$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 1)" != 0 ]; then
    # On a conflict, abort and keep local commits; session-start warns while commits stay unpushed.
    git pull --rebase -q || git rebase --abort
    git push -q
  fi
  # Refresh the qmd search index (cheap when nothing changed); also picks up notes pulled at session start.
  if command -v qmd >/dev/null; then qmd update && qmd embed; fi
} >/dev/null 2>&1 &
