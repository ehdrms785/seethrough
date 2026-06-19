#!/usr/bin/env bash
# seethrough uninstall — remove the SEETHROUGH block from CLAUDE.md (idempotent).
# Hooks are removed automatically when the plugin is uninstalled.
# Usage: uninstall.sh [global|local]
set -euo pipefail

scope="${1:-}"
if [ -z "$scope" ]; then
  printf "seethrough — remove block from: [l]ocal / [g]lobal: "
  read -r ans
  case "$ans" in g*|G*) scope=global;; *) scope=local;; esac
fi
case "$scope" in
  global) CLAUDE_MD="$HOME/.claude/CLAUDE.md";;
  local)  CLAUDE_MD="$PWD/CLAUDE.md";;
  *) echo "seethrough: scope must be global or local"; exit 1;;
esac
[ -f "$CLAUDE_MD" ] || { echo "seethrough: $CLAUDE_MD not found — nothing to remove."; exit 0; }

python3 - "$CLAUDE_MD" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
cur = p.read_text(encoding="utf-8")
new = re.sub(r"\n*<!-- SEETHROUGH:BEGIN.*?SEETHROUGH:END -->\n?", "\n", cur, flags=re.S)
p.write_text(new, encoding="utf-8")
print("  ✓ SEETHROUGH block removed" if new != cur else "  = no SEETHROUGH block (already removed)")
PY

echo "seethrough uninstall complete ($scope). Backups ($CLAUDE_MD.seethrough-bak.*) can be deleted manually."
