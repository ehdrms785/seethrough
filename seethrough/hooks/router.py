#!/usr/bin/env python3
"""seethrough router — UserPromptSubmit hook.
Reads {"prompt": "..."} on stdin. If the prompt matches a rule in
router-rules.json, prints that rule's guidance to stdout (which Claude Code
injects as context). Never blocks. Always exits 0."""
import sys, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # plugin root
RULES = ROOT / "hooks" / "router-rules.json"


def is_ascii_word(tok: str) -> bool:
    return all(ord(c) < 128 and (c.isalnum()) for c in tok)


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    prompt = (data.get("prompt") or "")
    if not prompt:
        return 0
    low = prompt.lower()

    try:
        rules = json.loads(RULES.read_text(encoding="utf-8")).get("rules", [])
    except Exception:
        return 0

    out = []
    for rule in rules:
        hit = False
        for kw in rule.get("keywords", []):
            kw = kw.lower()
            if is_ascii_word(kw):
                # word-boundary match for ascii tokens (avoids substring false positives)
                if re.search(r"\b" + re.escape(kw) + r"\b", low):
                    hit = True
                    break
            else:
                # CJK or symbol tokens: boundaries are ambiguous, use containment
                if kw in low:
                    hit = True
                    break
        if hit:
            msg = rule.get("message", "").replace("__PLUGIN_ROOT__", str(ROOT))
            if msg:
                out.append(msg)

    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
