#!/usr/bin/env bash
# seethrough verify.sh — deterministic acceptance gate.
# Exits 0 only if every assertion passes. This is the "done" signal an
# autonomous run polls: loop the build until `bash verify.sh` returns 0.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PY=python3
fail=0
pass=0
chk() { # chk "name" "expected" "actual"
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else
    echo "  ✗ FAIL: $1 — expected [$2] got [$3]"; fail=$((fail+1)); fi
}

echo "== router.py =="
out=$(echo '{"prompt":"help me debug this crash"}' | $PY "$ROOT/hooks/router.py"); rc=$?
chk "router debug → injects investigation" "1" "$(echo "$out" | grep -c investigation)"
chk "router always exit 0" "0" "$rc"
out=$(echo '{"prompt":"render an svg chart"}' | $PY "$ROOT/hooks/router.py")
chk "router svg → injects grounding" "1" "$(echo "$out" | grep -c grounding)"
out=$(echo '{"prompt":"write a haiku"}' | $PY "$ROOT/hooks/router.py")
chk "router no-signal → silent" "0" "$(echo -n "$out" | wc -c | tr -d ' ')"
echo 'garbage' | $PY "$ROOT/hooks/router.py" >/dev/null 2>&1
chk "router bad json → exit 0" "0" "$?"

echo "== finish-the-work.py =="
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"이제 폼을 구현하겠습니다."}]}}' > /tmp/v1.jsonl
out=$(echo '{"transcript_path":"/tmp/v1.jsonl","stop_hook_active":false}' | $PY "$ROOT/hooks/finish-the-work.py")
chk "promise-only → block" "1" "$(echo "$out" | grep -c '"decision": "block"')"
out=$(echo '{"transcript_path":"/tmp/v1.jsonl","stop_hook_active":true}' | $PY "$ROOT/hooks/finish-the-work.py")
chk "loop guard → pass" "0" "$(echo -n "$out" | wc -c | tr -d ' ')"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"구현했습니다. 더 진행할까요?"}]}}' > /tmp/v2.jsonl
out=$(echo '{"transcript_path":"/tmp/v2.jsonl","stop_hook_active":false}' | $PY "$ROOT/hooks/finish-the-work.py")
chk "ends with question → pass" "0" "$(echo -n "$out" | wc -c | tr -d ' ')"

echo "== goals.py gate =="
T="$(mktemp -d)"; (cd "$T"
  $PY "$ROOT/scripts/goals.py" create --brief x --goal "a::impl" --goal "v::verify" >/dev/null
  $PY "$ROOT/scripts/goals.py" next >/dev/null
  $PY "$ROOT/scripts/goals.py" checkpoint --id G001 --status complete --evidence "" >/dev/null 2>&1
  echo "noevi=$?"
  $PY "$ROOT/scripts/goals.py" checkpoint --id G001 --status complete --evidence "ok" >/dev/null 2>&1
  echo "evi=$?"
  $PY "$ROOT/scripts/goals.py" next >/dev/null
  $PY "$ROOT/scripts/goals.py" checkpoint --id G002 --status complete --evidence "ok" >/dev/null 2>&1
  echo "noverify=$?"
  $PY "$ROOT/scripts/goals.py" checkpoint --id G002 --status complete --evidence "ok" --verify-cmd "t" --verify-evidence "pass" >/dev/null 2>&1
  echo "verify=$?"
) > /tmp/gout
chk "complete w/o evidence → refused(1)" "1" "$(grep noevi /tmp/gout | cut -d= -f2)"
chk "complete w/ evidence → ok(0)" "0" "$(grep '^evi' /tmp/gout | cut -d= -f2)"
chk "final w/o verify → refused(1)" "1" "$(grep noverify /tmp/gout | cut -d= -f2)"
chk "final w/ verify → ok(0)" "0" "$(grep '^verify' /tmp/gout | cut -d= -f2)"

echo "== setup.sh idempotency =="
W="$(mktemp -d)"; ( cd "$W"; export CLAUDE_PLUGIN_ROOT="$ROOT"
  printf '# proj\nnotes\n' > CLAUDE.md
  bash "$ROOT/setup/setup.sh" local >/dev/null 2>&1
  bash "$ROOT/setup/setup.sh" local >/dev/null 2>&1
  echo "blocks=$(grep -c 'SEETHROUGH:BEGIN' CLAUDE.md)"
  echo "notes=$(grep -c 'notes' CLAUDE.md)"
  bash "$ROOT/setup/uninstall.sh" local >/dev/null 2>&1
  echo "after=$(grep -c 'SEETHROUGH:BEGIN' CLAUDE.md)"
) > /tmp/sout
chk "setup idempotent → 1 block" "1" "$(grep '^blocks' /tmp/sout | cut -d= -f2)"
chk "setup preserves content" "1" "$(grep '^notes' /tmp/sout | cut -d= -f2)"
chk "uninstall removes block" "0" "$(grep '^after' /tmp/sout | cut -d= -f2)"

echo "== no star feature in plugin files =="
star=$(grep -rIl -i 'starred\|/user/starred' "$ROOT/hooks" "$ROOT/scripts" "$ROOT/setup" "$ROOT/commands" "$ROOT/.claude-plugin" 2>/dev/null | wc -l | tr -d ' ')
chk "no star code in non-md files" "0" "$star"

echo "-----------------------------------"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "✓ ALL GREEN"; exit 0; } || { echo "✗ FAILURES"; exit 1; }
