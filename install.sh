#!/bin/bash
# Usage: ./install.sh <notes-vault> [<platform-vault>]
# Links the skills and installs the hooks into ~/.claude for the notes vault and, optionally, the platform graph vault.
# Safe to re-run; each run rebuilds the hooks from its arguments, so leaving out the platform vault turns it off.
# Re-run after repos/claude/setup.sh (it overwrites ~/.claude/settings.json), after pulling changes to hooks/,
# and after changing the Node version.
set -e
usage() {
  echo "Usage: $0 <notes-vault> [<platform-vault>]"
  echo "Each vault must be the top folder of a git repo with an upstream branch: the Stop hook commits and pushes all of it."
  exit 1
}
# Prints the vault's absolute path, or fails unless it is a repo's top folder with an upstream branch.
vault_dir() {
  local dir cdup
  dir="$(cd "$1" 2>/dev/null && pwd)" || return 1
  cdup=$(git -C "$dir" rev-parse --show-cdup 2>/dev/null) && [ -z "$cdup" ] || return 1
  git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || return 1
  echo "$dir"
}
VAULT=$(vault_dir "${1:-}") || usage
PLATFORM=""
if [ -n "${2:-}" ]; then
  PLATFORM=$(vault_dir "$2") || usage
fi
CODE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
HOOKS="$HOME/.claude/hooks/knowledge-vault"

mkdir -p "$HOME/.claude/skills" "$HOOKS"
ln -sfn "$CODE/skills/knowledge-vault" "$HOME/.claude/skills/knowledge-vault"
# Hooks run without permission checks, so run copies: a git pull or an edit in this repo changes nothing until re-install.
cp "$CODE/hooks/session-start.sh" "$CODE/hooks/sync.sh" "$HOOKS/"
chmod +x "$HOOKS/"*.sh
mkdir -p "$VAULT/topics"
if [ -n "$PLATFORM" ]; then
  ln -sfn "$CODE/skills/platform-graph" "$HOME/.claude/skills/platform-graph"
  mkdir -p "$PLATFORM/services" "$PLATFORM/kafka" "$PLATFORM/apis" "$PLATFORM/databases" "$PLATFORM/flows" "$PLATFORM/.obsidian"
else
  rm -f "$HOME/.claude/skills/platform-graph"
fi

# Optional qmd search (npm install -g @tobilu/qmd): register the vaults and pass qmd's folder to the sync hook,
# since hooks may not get the shell profile's PATH.
QMD_DIR=""
if command -v qmd >/dev/null; then
  QMD_DIR="$(dirname "$(command -v qmd)")"
  qmd collection list | grep '^vault ' >/dev/null || qmd collection add "$VAULT" --name vault --mask "projects/**/*.md,topics/**/*.md"
  qmd context add qmd://vault "Personal knowledge vault: project notes (current state), session notes (what was done and how), answers and cross-project topic pages from the user's software work" >/dev/null
  if [ -n "$PLATFORM" ]; then
    qmd collection list | grep '^platform ' >/dev/null || qmd collection add "$PLATFORM" --name platform --mask "services/**/*.md,kafka/**/*.md,apis/**/*.md,databases/**/*.md,flows/**/*.md"
    qmd context add qmd://platform "Platform knowledge graph: services, Kafka topics, APIs, databases and business flows, and how they connect" >/dev/null
  fi
fi

python3 - "$VAULT" "$SETTINGS" "$HOOKS" "$QMD_DIR" "$PLATFORM" <<'EOF'
import json, os, sys
vault, path, hooks_dir, qmd_dir, platform = sys.argv[1:6]
with open(path) as f:
    s = json.load(f)
hooks = s.setdefault("hooks", {})
env = f'VAULT="{vault}" ' + (f'PLATFORM_VAULT="{platform}" ' if platform else "")
for event, script in (("SessionStart", "session-start.sh"), ("Stop", "sync.sh")):
    entries = [e for e in hooks.get(event, [])
               if not any(script in h.get("command", "") and ("knowledge-vault" in h["command"] or vault in h["command"])
                          for h in e.get("hooks", []))]
    path_env = f'PATH="{qmd_dir}:$PATH" ' if qmd_dir and script == "sync.sh" else ""
    entries.append({"hooks": [{"type": "command", "command": f'{env}{path_env}"{hooks_dir}/{script}"'}]})
    hooks[event] = entries
# Claude may write notes only; everything else in the vaults stays behind a permission prompt.
dirs = s.setdefault("permissions", {}).setdefault("additionalDirectories", [])
dirs[:] = [d for d in dirs if d != vault]
folders = [f"{vault}/projects", f"{vault}/topics"]
if platform:
    folders += [f"{platform}/{n}" for n in ("services", "kafka", "apis", "databases", "flows")]
for d in folders:
    if d not in dirs:
        dirs.append(d)
with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
    f.write("\n")

# Graph colours by node type; keeps the user's own groups and settings, replaces ours by query.
if platform:
    gpath = f"{platform}/.obsidian/graph.json"
    g = json.load(open(gpath)) if os.path.exists(gpath) else {}
    ours = {"path:services": 5214967, "path:kafka": 15769648, "path:apis": 11566832,
            "path:databases": 8947848, "path:flows": 4174719}
    g["colorGroups"] = [c for c in g.get("colorGroups", []) if c.get("query") not in ours] + \
        [{"query": q, "color": {"a": 1, "rgb": rgb}} for q, rgb in ours.items()]
    with open(gpath, "w") as f:
        json.dump(g, f, indent=2)
        f.write("\n")
EOF

echo "Installed: skills, hook copies in $HOOKS, SessionStart + Stop hooks and notes access in $SETTINGS"
[ -n "$PLATFORM" ] && echo "Platform vault: $PLATFORM (graph colours set)" || echo "Platform vault: off"
[ -n "$QMD_DIR" ] && echo "qmd: collections registered" || echo "qmd: not installed, search falls back to Grep"
