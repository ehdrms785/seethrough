#!/usr/bin/env python3
"""seethrough finish-the-work — Stop hook.
Detects an early stop where the assistant only PROMISES work without doing it,
and re-engages it via {"decision":"block"}. Deterministic (regex).
stop_hook_active guards against infinite loops."""
import sys, json, re


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    # Loop guard: if we already forced one continuation, do not block again.
    if data.get("stop_hook_active"):
        return 0

    tpath = data.get("transcript_path") or ""
    if not tpath:
        return 0
    try:
        last_text, last_had_tool = "", False
        with open(tpath, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                msg = obj.get("message", obj)
                if obj.get("type") == "assistant" or msg.get("role") == "assistant":
                    content = msg.get("content", [])
                    if isinstance(content, list):
                        texts = [b.get("text", "") for b in content
                                 if isinstance(b, dict) and b.get("type") == "text"]
                        tools = [b for b in content
                                 if isinstance(b, dict) and b.get("type") == "tool_use"]
                        if texts or tools:
                            last_text = "\n".join(texts).strip()
                            last_had_tool = bool(tools)
    except Exception:
        return 0

    # Ended with a tool call (still working) or with no text -> not an early stop.
    if last_had_tool or not last_text:
        return 0

    tail = last_text[-400:]

    # Future/intent promise (English + Korean). Past tense excluded by design.
    promise = re.search(
        r"\b(i'?ll|i will|let me|next,? i|now i'?ll)\b[^.]{0,60}\b"
        r"(now|next|then|implement|create|write|add|run|fix|save|build|start|proceed)\b",
        tail, re.IGNORECASE,
    ) or re.search(r"(이제|다음으로|곧)\s*[^.]{0,40}(하겠|할게|구현|작성|추가|실행|수정|진행)", tail)

    # A legitimate stop that ends by asking the user passes through.
    asks_user = re.search(
        r"(\?|shall i|would you like|do you want|let me know|which option|할까요|하시겠|원하시면|알려주세요)",
        tail, re.IGNORECASE,
    )

    if promise and not asks_user:
        out = {
            "decision": "block",
            "reason": ("Your previous response ended by stating an intent to do work "
                       "without actually doing it. Do that work now with tool calls. "
                       "End the turn only when the task is complete or you are blocked "
                       "on input that only the user can provide."),
        }
        sys.stdout.write(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
