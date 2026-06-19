#!/usr/bin/env bash
# seethrough always-on setup — inject the operating block into CLAUDE.md
# (idempotent, with backup). Does NOT touch settings.json. No GitHub star.
# Usage: setup.sh [global|local]   (no arg = interactive; default local)
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BLOCK_TPL="$ROOT/setup/operating-block.md"

command -v python3 >/dev/null 2>&1 || { echo "seethrough: python3 is required."; exit 1; }
[ -f "$BLOCK_TPL" ] || { echo "seethrough: block template not found ($BLOCK_TPL)"; exit 1; }

scope="${1:-}"
if [ -z "$scope" ]; then
  printf "seethrough — inject into: [l]ocal (this project, recommended) / [g]lobal (all projects): "
  read -r ans
  case "$ans" in g*|G*) scope=global;; l*|L*|"") scope=local;; *) echo "cancelled"; exit 1;; esac
fi
case "$scope" in
  global) CLAUDE_MD="$HOME/.claude/CLAUDE.md";;
  local)  CLAUDE_MD="$PWD/CLAUDE.md";;
  *) echo "seethrough: scope must be global or local"; exit 1;;
esac
echo "seethrough → $scope ($CLAUDE_MD)"

mkdir -p "$(dirname "$CLAUDE_MD")"; touch "$CLAUDE_MD"
ts=$(python3 -c "import time;print(int(time.time()))")
cp "$CLAUDE_MD" "$CLAUDE_MD.seethrough-bak.$ts" && echo "  backup: $CLAUDE_MD.seethrough-bak.$ts"

python3 - "$CLAUDE_MD" "$BLOCK_TPL" "$ROOT" <<'PY'
import sys, re, pathlib
md, tpl, root = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(md)
cur = p.read_text(encoding="utf-8") if p.exists() else ""
block = pathlib.Path(tpl).read_text(encoding="utf-8").strip().replace("__PLUGIN_ROOT__", root)
cur = re.sub(r"<!-- SEETHROUGH:BEGIN.*?SEETHROUGH:END -->\n?", "", cur, flags=re.S).rstrip()
p.write_text((cur + "\n\n" + block + "\n") if cur else (block + "\n"), encoding="utf-8")
print("  ✓ CLAUDE.md: SEETHROUGH operating block injected (idempotent)")
PY

mkdir -p "$HOME/.seethrough"
python3 - "$scope" "$ts" <<'PY'
import json, sys, os
p = os.path.expanduser("~/.seethrough/progress.json")
json.dump({"setup_done": True, "scope": sys.argv[1], "version": "0.1.0", "ts": int(sys.argv[2])}, open(p, "w"))
PY

echo "seethrough setup complete ($scope) — applies from the next session."
echo "  state: ~/.seethrough/progress.json"
echo "  Uninstall: bash $ROOT/setup/uninstall.sh $scope"
echo "  Note: hooks (router + finish-the-work) are auto-registered via hooks.json on plugin install."
