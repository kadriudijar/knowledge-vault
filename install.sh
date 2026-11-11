#!/bin/bash
# Usage: ./install.sh <vault-path>
# Links the knowledge-vault skill and installs the hooks into ~/.claude for the vault (the notes repo). Safe to re-run.
# Re-run after repos/claude/setup.sh (it overwrites ~/.claude/settings.json), after pulling changes to hooks/,
# and after changing the Node version.
set -e
[ -d "${1:-}" ] || { echo "Usage: $0 <vault-path>"; exit 1; }
VAULT="$(cd "$1" && pwd)"
CODE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
HOOKS="$HOME/.claude/hooks/knowledge-vault"

mkdir -p "$HOME/.claude/skills" "$HOOKS"
ln -sfn "$CODE/skills/knowledge-vault" "$HOME/.claude/skills/knowledge-vault"
# Hooks run without permission checks, so run copies: a git pull or an edit in this repo changes nothing until re-install.
cp "$CODE/hooks/session-start.sh" "$CODE/hooks/sync.sh" "$HOOKS/"
chmod +x "$HOOKS/"*.sh
mkdir -p "$VAULT/topics"

# Optional qmd search (npm install -g @tobilu/qmd): register the vault and pass qmd's folder to the sync hook,
# since hooks may not get the shell profile's PATH.
QMD_DIR=""
if command -v qmd >/dev/null; then
  QMD_DIR="$(dirname "$(command -v qmd)")"
  qmd collection list | grep '^vault ' >/dev/null || qmd collection add "$VAULT" --name vault --mask "projects/**/*.md,topics/**/*.md"
  qmd context add qmd://vault "Personal knowledge vault: project notes (current state), session notes (what was done and how), answers and cross-project topic pages from the user's software work" >/dev/null
fi

python3 - "$VAULT" "$SETTINGS" "$HOOKS" "$QMD_DIR" <<'EOF'
import json, sys
vault, path, hooks_dir, qmd_dir = sys.argv[1:5]
with open(path) as f:
    s = json.load(f)
hooks = s.setdefault("hooks", {})
for event, script in (("SessionStart", "session-start.sh"), ("Stop", "sync.sh")):
    entries = [e for e in hooks.get(event, [])
               if not any(script in h.get("command", "") and ("knowledge-vault" in h["command"] or vault in h["command"])
                          for h in e.get("hooks", []))]
    path_env = f'PATH="{qmd_dir}:$PATH" ' if qmd_dir and script == "sync.sh" else ""
    entries.append({"hooks": [{"type": "command", "command": f'VAULT="{vault}" {path_env}"{hooks_dir}/{script}"'}]})
    hooks[event] = entries
# Claude may write notes only; everything else in the vault stays behind a permission prompt.
dirs = s.setdefault("permissions", {}).setdefault("additionalDirectories", [])
dirs[:] = [d for d in dirs if d != vault]
for d in (f"{vault}/projects", f"{vault}/topics"):
    if d not in dirs:
        dirs.append(d)
with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF

echo "Installed: skill link, hook copies in $HOOKS, SessionStart + Stop hooks and notes access in $SETTINGS"
[ -n "$QMD_DIR" ] && echo "qmd: vault collection registered" || echo "qmd: not installed, search falls back to Grep"
