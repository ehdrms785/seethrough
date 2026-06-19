# `seethrough` — Claude Code 플러그인 빌드 명세서

> **이 문서의 사용법 (Claude Code에게)**
> 너는 이 명세서를 받아 `seethrough`라는 Claude Code 플러그인을 **제로부터 구현**한다.
> 아래 파일 트리·파일별 명세·참조 구현·수용 기준을 그대로 따른다.
> 참조 구현이 제공된 파일은 그 코드를 기준으로 하되, 동작 계약(입출력·exit code·게이트 규칙)을 절대 바꾸지 않는다.
> 모든 동작은 "수용 기준" 섹션의 테스트를 통과해야 한다.
> 플러그인 이름 `seethrough`는 사용자가 원하면 바꿔도 되지만, 바꾼다면 **모든 파일에서 일관되게** 바꾼다.

---

## 1. 목적과 철학 (왜 만드는가)

이 플러그인은 LLM 코딩 에이전트의 **능력(capability)이 아니라 규율(discipline)의 실패**를 막는 하네스다. 모델이 "할 수 없어서"가 아니라 "안 해서" 건너뛰는 절차들 — 실행해보지 않고 완료 선언, 약속만 하고 턴 종료, 증상만 고친 버그 수정, 긴 작업 중 진행 상황 분실 — 을 강제한다.

핵심 원칙은 단 하나다:

> **모델의 선의에 맡기지 말고, 기계적으로 판정 가능한 규율은 호스트가 강제하는 결정론적 관문(gate)으로 바꾼다. 판정 불가능한 규율만 컨텍스트 주입(soft)으로 안내하되, 관련 있을 때만 주입한다.**

비유: "배포 전에 테스트 꼭 돌려"라고 말로 부탁하는 것(soft)과, 테스트가 초록불이 아니면 머지가 안 되는 CI 게이트(hard)의 차이. 가장 자주·치명적으로 빠뜨리는 규율일수록 hard 쪽에 둔다.

이 하네스는 모델의 천장을 올리지 않는다. 모델이 자기 천장까지 가도록 만들 뿐이다. 천장(열린 창의성, 사양 밖 발견)이 막는 지점에서는 솔직히 한계를 보고하고 escalate하도록 만든다.

---

## 2. 설계 원칙 (구현 판단의 기준)

구현 중 판단이 필요할 때 아래 원칙으로 결정한다.

1. **Hard vs Soft 분류.** 기계적으로 판정 가능한가?
   - 가능(예: "방금 약속만 했나", "증거 필드가 비었나") → **hard**: 훅 또는 코드 게이트.
   - 불가능(예: "가설을 3개 세웠나", "렌더가 *올바른가*") → **soft**: 컨텍스트 주입 텍스트.
2. **강제 강도 = 실패 빈도 × 비용.** 가장 흔하고 비싼 실패(조기 종료)에 가장 강한 강제(Stop 훅).
3. **전달 표면을 활성화 신뢰도로 선택.** 신뢰도 순: 훅(항상·결정론) > CLAUDE.md 상주(항상·soft) > 스킬(조건부·모델 선택) > 라우터 매칭 팩(조건부·soft).
4. **외부 상태는 컨텍스트 손실이 치명적인 곳에만.** 멀티스텝 진행 상황은 디스크에 영속(세션 사망에도 복구). 1회성 체크엔 파일 상태를 만들지 않는다.
5. **설치는 멱등·가역·fail-silent.** 사용자 파일(CLAUDE.md)을 건드릴 땐 백업·마커로 감싸 재주입·깨끗한 제거. 부수 기능 실패가 본 흐름을 막지 않는다.
6. **확장 가능하게.** 라우터 규칙은 코드 하드코딩이 아니라 외부 데이터(`router-rules.json`)로 둔다. 새 규율 추가 = 설정 한 줄.
7. **천장 정직성.** 같은 문제에 2회 막히면 "능력 문제다, escalate하라"고 안내.

### 원본 `fablize`와 의도적으로 다르게 하는 점 (반드시 반영)

- **Stop 훅을 명시 등록한다.** 원본은 early-stop 훅이 "보통 전역에 이미 등록돼 있겠지"에 기댄다(가장 약한 고리). 우리는 `hooks/hooks.json`에 **router(UserPromptSubmit)와 finish-the-work(Stop)를 둘 다** 등록한다.
- **라우터를 데이터 주도로.** 키워드→팩 매핑을 `case` 문 하드코딩이 아니라 `hooks/router-rules.json`에서 읽는다.
- **단어 경계 매칭.** substring 매칭(`error`가 무관한 산문에도 걸림)을 피하고 단어 경계(`\b`) 정규식으로 오탐을 줄인다.
- **훅은 순수 Python으로.** bash/python 혼합 대신, 훅을 `python3`으로 직접 실행한다(테스트·유지보수 용이).
- **star 자동 주입 기능은 완전히 제외한다.** (아래 §3)

---

## 3. 제외 사항 (명확히)

**GitHub star 자동 주입 기능은 구현하지 않는다.** 원본의 `setup/star.sh`, 설치 시 `gh api -X PUT /user/starred/...` 자동 실행, 설치 질문에 ⭐를 붙여 동의를 흐릿하게 받는 패턴 — 전부 만들지 않는다. 이유: 부수 행위(홍보)를 주 기능(설치)에 묶고 동의 UX를 흐리는 것은 안티패턴이기 때문이다. 설치는 오직 "운영 블록 주입 + 상태 기록"만 한다.

---

## 4. 전체 파일 트리

```
seethrough/
├── .claude-plugin/
│   ├── plugin.json            # 플러그인 매니페스트 (스킬 등록)
│   └── marketplace.json       # 마켓플레이스 등록 (선택, 로컬 배포면 생략 가능)
├── hooks/
│   ├── hooks.json             # 훅 등록: UserPromptSubmit→router, Stop→finish-the-work
│   ├── router.py              # [hard] 퍼-태스크 라우터 (데이터 주도, 단어 경계)
│   ├── router-rules.json      # 라우터 키워드→팩 매핑 (외부 데이터)
│   └── finish-the-work.py     # [hard] 조기 종료(약속만 함) 차단 Stop 훅
├── packs/
│   ├── investigation-protocol.md      # [soft] 디버깅 규율
│   └── verification-grounding.md      # [soft] 렌더/실행 산출물 검증 규율
├── scripts/
│   └── goals.py               # [hard] 멀티스토리 검증 게이트 엔진 (stdlib)
├── skills/
│   └── seethrough/
│       └── SKILL.md           # 스킬 진입점·오케스트레이션
├── setup/
│   ├── operating-block.md     # CLAUDE.md에 주입할 상시 운영 블록 템플릿
│   ├── setup.sh               # 멱등 설치 (star 없음)
│   └── uninstall.sh           # 멱등 제거
├── commands/
│   └── setup.md               # /seethrough:setup 슬래시 커맨드
├── .gitignore
└── README.md
```

런타임 상태(`./.seethrough/`)와 백업(`*.seethrough-bak.*`)은 git에서 제외한다.

---

## 5. 훅 계약 기초 (Claude Code 훅이 어떻게 동작하는가)

구현 전 반드시 숙지한다. (Claude Code 공식 동작 기준)

- 훅은 **stdin으로 JSON 이벤트를 받고, exit code와 stdout JSON으로 신호**를 돌려주는 명령이다.
- 생명주기 박자: 세션 단위(`SessionStart`/`SessionEnd`), 턴 단위(`UserPromptSubmit`/`Stop`), 도구 호출 단위(`PreToolUse`/`PostToolUse`).
- **차단(block) 가능 이벤트:** `PreToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `PreCompact`.
- **`UserPromptSubmit`와 `SessionStart`에서는 stdout이 컨텍스트로 모델에 주입**된다. (→ 라우터는 stdout에 안내 텍스트를 쓴다.)
- 차단 신호: **exit code 2**, 또는 **stdout에 `{"decision":"block","reason":"..."}`** JSON. (→ finish-the-work는 후자를 쓴다.)
- `Stop` 훅 입력에는 `transcript_path`(대화 기록 JSONL 경로)와 `stop_hook_active`(이 훅이 이미 한 번 차단을 걸었는지)가 들어온다. **무한 루프 방지를 위해 `stop_hook_active`가 참이면 즉시 통과한다.**
- 플러그인 훅은 `${CLAUDE_PLUGIN_ROOT}`(런타임 주입 변수)로 자기 경로를 참조한다.
- 훅은 샌드박스 없이 사용자 권한으로 실행된다. 작게·명시적으로·실패에 안전하게 작성한다.

---

## 6. 파일별 상세 명세 + 참조 구현

### 6.1 `.claude-plugin/plugin.json`

**역할:** 플러그인 매니페스트. 호스트가 설치·로드 시 읽어 스킬을 등록한다.
**참조 구현:**

```json
{
  "name": "seethrough",
  "version": "0.1.0",
  "description": "A harness that enforces completion, evidence, and verification as procedure. Auto-routes the right discipline per task: a multi-story evidence gate, an investigation protocol, render-output verification grounding, and an early-stop guard. It does not fake model capability — at the ceiling it tells you to escalate.",
  "author": { "name": "<YOUR_NAME>", "email": "<YOUR_EMAIL>" },
  "keywords": ["harness", "verification", "completion", "agentic", "discipline"],
  "skills": ["./skills/seethrough"]
}
```

### 6.2 `.claude-plugin/marketplace.json` (선택)

**역할:** `/plugin marketplace add`로 배포할 때만 필요. 로컬 설치만 할 거면 생략 가능.
**참조 구현:**

```json
{
  "name": "seethrough",
  "owner": { "name": "<YOUR_NAME>", "email": "<YOUR_EMAIL>" },
  "metadata": {
    "description": "seethrough — completion/evidence/verification enforced as procedure",
    "version": "0.1.0"
  },
  "plugins": [
    {
      "name": "seethrough",
      "source": "./",
      "description": "Multi-story evidence gate, investigation protocol, verification grounding, early-stop guard, per-task routing.",
      "category": "workflow"
    }
  ]
}
```

### 6.3 `hooks/hooks.json`

**역할:** 훅 등록. **router와 finish-the-work를 둘 다** 등록한다(원본과 다른 핵심 지점).
**호출 시점:** 플러그인 설치 시 호스트가 자동 등록.
**참조 구현:**

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/router.py\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/finish-the-work.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### 6.4 `hooks/router-rules.json` (라우터 외부 데이터)

**역할:** 키워드→팩 매핑을 코드 밖 데이터로 분리. 새 규율 추가는 이 파일에 항목 하나 추가로 끝난다.
**규칙:** 각 항목은 `id`, `keywords`(단어 경계로 매칭할 소문자 토큰 목록), `message`(매칭 시 stdout에 주입할 안내 문장). `message` 안의 `__PLUGIN_ROOT__`는 라우터가 런타임에 실제 경로로 치환한다.
**참조 구현:**

```json
{
  "rules": [
    {
      "id": "investigation",
      "keywords": ["debug", "bug", "error", "traceback", "crash", "failing", "stacktrace", "regression", "버그", "디버그", "에러", "오류"],
      "message": "[seethrough:investigation] 디버깅/근본원인 신호 감지 — __PLUGIN_ROOT__/packs/investigation-protocol.md 를 따른다: 먼저 재현 → 3개 이상의 경쟁 가설 → 가설별 증거 수집 → 전체 인과 사슬 추적(증상 제거 ≠ 결함 제거) → 수정 전후 검증 → 기각한 가설까지 보고."
    },
    {
      "id": "grounding",
      "keywords": ["html", "svg", "game", "canvas", "chart", "render", "website", "webpage", "ui", "animation", "렌더", "차트", "게임"],
      "message": "[seethrough:grounding] 렌더/실행 산출물 신호 감지 — __PLUGIN_ROOT__/packs/verification-grounding.md 의 그라운딩 루프를 따른다: 실제 렌더러에서 실행 → 실제 출력을 직접 관찰 → 관찰이 드러낸 결함만 수정 → 재실행. 정적 검사(well-formed)는 관찰(correct)이 아니다."
    }
  ]
}
```

### 6.5 `hooks/router.py`

**역할:** `UserPromptSubmit` 훅. 프롬프트를 보고 매칭되는 규율 안내만 컨텍스트에 주입한다.
**호출 시점:** 매 프롬프트 제출 시.
**동작 계약(절대 불변):**
- stdin JSON에서 `prompt` 문자열을 읽는다(없으면 빈 문자열, 그냥 통과).
- 소문자화 후 `router-rules.json`의 각 규칙에 대해 **단어 경계 매칭**(`\bkeyword\b`)을 수행. 단, 한글처럼 단어 경계가 모호한 토큰은 단순 포함으로 처리(아래 구현 참고).
- 매칭된 규칙들의 `message`(경로 치환 후)를 줄바꿈으로 합쳐 **stdout에 출력**(이게 컨텍스트로 주입됨).
- 매칭이 없으면 아무것도 출력하지 않는다.
- **어떤 경우에도 exit 0.** 라우터는 절대 차단하지 않는다(fail-silent).
- 규칙 파일이 없거나 깨져도 조용히 통과(exit 0).

**참조 구현:**

```python
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
```

### 6.6 `hooks/finish-the-work.py`

**역할:** `Stop` 훅. 모델이 "이제 X 하겠습니다"라고 **약속만 하고 턴을 끝내는 조기 종료**를 잡아 다시 일하게 만든다.
**호출 시점:** 턴 종료 시(모델이 응답을 끝냈다고 판단할 때).
**동작 계약(절대 불변):**
- stdin JSON에서 `transcript_path`, `stop_hook_active`를 읽는다.
- **`stop_hook_active`가 참이면 즉시 통과(exit 0).** (무한 루프 방지 — 우리가 이미 한 번 재engage시켰으면 다시 막지 않는다.)
- `transcript_path`가 없거나 파일이 없으면 통과.
- transcript(JSONL)를 끝까지 읽어 **마지막 assistant 메시지**의 텍스트와 "도구 호출로 끝났는지"를 추출.
- **도구 호출로 끝났거나(아직 작업 중) 텍스트가 없으면 통과.**
- 마지막 메시지의 **끝부분(약 400자)** 만 검사한다(리포트 전체가 아니라 닫는 문단).
- 끝부분에 **미래/의도형 약속 패턴**(예: `I'll …`, `let me …`, "이제 …하겠다")이 있고, **사용자에게 질문하며 끝나지 않으면**(`?`, "할까요", "원하시면" 등) → **`{"decision":"block","reason":"..."}` 를 stdout에 출력**.
- 그 외에는 통과(exit 0). 파싱 실패 등 예외도 전부 통과.

> 주의: 정규식 차단은 거칠어서 선언형 제안("원하시면 리포트 쓸게요")에 오발할 수 있다. 그래서 "질문으로 끝나면 통과" 예외를 둔다. 과거형("작성했다")은 약속이 아니므로 매칭하지 않는다.

**참조 구현:**

```python
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
```

### 6.7 `packs/investigation-protocol.md` (soft)

**역할:** 디버깅 시 모델이 따를 조사 규율. 라우터가 신호 감지 시 안내하거나, 스킬이 읽으라 지시한다.
**참조 내용(자기 말로 작성, 동일 취지 유지):**

```markdown
# 조사 프로토콜 (디버깅 / 근본 원인 / 리뷰)

버그를 다룰 때 다음 규율을 따른다.

1. **재현 먼저.** 어떤 가설도 세우기 전에 실패 케이스를 실제로 돌려 실제 출력을 읽는다.
2. **경쟁 가설을 먼저 여러 개.** 하나를 파기 전에 최소 3개의 가설을 세운다. 알려진 실패와 패턴이 같아 보여도 원인은 다를 수 있다. 로그에서 가장 눈에 띄는 신호가 곧 근본 원인은 아니다 — 그것도 여러 가설 중 하나로 취급한다.
3. **가설별 증거.** 각 가설을 확증/반증할 증거가 무엇인지 정하고, 관련 코드 경로를 끝까지 읽어 그 증거를 모은다. 증거가 쌓이면 가설별 확신도를 갱신한다.
4. **전체 인과 사슬 추적.** 첫 그럴듯한 원인에서 멈추지 않는다. 그 원인이 어떻게 이 증상을 만들었는지, 눈에 보이는 트리거만 제거하면 결함이 잠복으로 남는지 묻는다. 테스트를 통과시키는 수정이 곧 결함을 제거하는 수정은 아니다.
5. **수정 전후 검증.** 코드를 바꾸기 전에 근본 원인을 증거로 확정한다. 수정 후에는 트리거 조건이 사라진 게 아니라 **실패 양상 자체가 사라졌음**을 증거로 보인다.
6. **기각한 가설 보고.** 보고서에 기각한 가설과 그것을 기각한 증거를 적는다. (리뷰의 경우 확신도 낮은 발견까지 전부 보고하고, 필터링은 별도 단계에서 한다.)
```

### 6.8 `packs/verification-grounding.md` (soft)

**역할:** 실행해야 맞는지 알 수 있는 산출물(HTML/SVG/게임/UI/차트/관찰 가능한 출력 스크립트)에 대한 검증 규율.
**참조 내용:**

```markdown
# 검증 그라운딩 (렌더/실행 산출물)

실행하거나 렌더해야만 정확성을 확인할 수 있는 산출물을 만들 때 — HTML, SVG, 게임, UI, 차트, 관찰 가능한 출력이 있는 스크립트, 애니메이션 — 파일을 쓰고 "열어보세요"로 끝내지 않는다. 완료를 선언하기 전에 자연 실행 환경에서 직접 돌려 실제 출력을 관찰한다.

이것은 추가 테스트가 아니라 **검증 양식(modality)**이다. 핵심은 "테스트를 더 써라"가 아니라 "그것이 실제로 동작하는 걸 보라"다. 정적 파싱(xmllint, node --check 등)은 파일이 well-formed임을 확인할 뿐, 보이거나 동작하는 모습이 correct함을 확인하지 못한다. well-formed와 correct는 다른 주장이다.

완료 전 그라운딩 루프:

1. **실제 렌더러에서 실행.** 웹 산출물은 헤드리스 브라우저(스크린샷)나 서브 후 탐색. SVG는 PNG로 렌더. 스크립트는 실행해 stdout/stderr 캡처. 애니메이션·게임은 모션/상태가 실제로 시작될 만큼 구동.
2. **출력을 관찰.** 스크린샷을 되읽고, 콘솔 에러를 읽고, 실제로 무엇이 렌더됐는지 본다 — 레이아웃이 온전한가, 무언가 가려졌나, 게임이 시작됐나, 정적 검사가 못 잡는 런타임 에러가 있나. 스크린샷을 만든 것 ≠ 본 것. 실제로 봐야 한다.
3. **관찰이 드러낸 것을 수정하고 재실행.** 런타임에만 보이는 결함(보드를 덮는 오버레이, 콘솔 에러, 깨진 레이아웃)이 이 루프가 잡으려는 바로 그것이다.

순수 텍스트·산문·설정·자체 테스트가 있는 로직에는 적용하지 않는다(그건 테스트 실행이 그라운딩). 트리거는 "실행될 때만 드러나는 방식으로 잘못 보이거나 잘못 동작할 수 있는가?"다. 그렇다면 끝내기 전에 돌려서 본다.

한 번 깨끗이 관찰했으면 멈춘다. 결함 없는 산출물을 N번 재검증하는 것은 출력을 바꾸지 않고 토큰만 낭비한다. 무언가를 바꿨을 때만 재실행한다.
```

### 6.9 `scripts/goals.py` (hard 게이트 엔진)

**역할:** 멀티스토리 작업을 순차 스토리로 분해하고, 증거 없는 완료를 코드로 거부하는 검증 게이트. 모델이 bash로 직접 실행한다.
**호출 시점:** 모델이 2개 이상 순차 스토리가 있는 작업을 시작할 때(스킬/운영 블록의 지시에 따라).
**동작 계약(절대 불변):**
- 상태는 **`./.seethrough/`** 에 영속(`goals.json` + `ledger.jsonl`). 저장소 루트에서 실행. 세션이 죽어도 `status`로 복구 가능.
- CLI: `create / next / checkpoint / status`.
- `create`: `--brief`와 1개 이상의 `--goal "title::objective"`. 형식 틀리면 거부. 이미 계획이 있으면 `--force` 없이는 거부.
- `next`: 다음 pending 스토리를 in_progress로 활성화하고 핸드오프 출력. 마지막 스토리면 "검증 게이트" 안내.
- `checkpoint --id Gxxx --status complete|failed|blocked --evidence "..."`:
  - 활성(in_progress) 스토리만 체크포인트 가능.
  - `complete`는 **비어있지 않은 `--evidence` 필수**(없으면 `sys.exit`로 거부).
  - **마지막 스토리**의 `complete`는 **`--verify-cmd`와 `--verify-evidence` 둘 다 필수**(없으면 거부). ← 검증 게이트의 핵심.
- `status`: 진행 현황 출력(복구 시 첫 명령).

**참조 구현:**

```python
#!/usr/bin/env python3
"""seethrough goal engine — a self-contained, stdlib-only multi-story loop
with a verification gate.

  - Decompose a task into sequential stories, persisted to ./.seethrough/.
  - A story can be checkpointed only after `next` activates it.
  - A `complete` checkpoint requires non-empty evidence.
  - The final story cannot complete without a verify command + result.

Usage:
  goals.py create --brief "..." --goal "title::objective" [--goal ...]
  goals.py next
  goals.py checkpoint --id G001 --status complete|failed|blocked --evidence "..."
                      [--verify-cmd "<command>" --verify-evidence "<result>"]
  goals.py status
"""
import argparse, json, sys
from datetime import datetime, timezone
from pathlib import Path

DIR = Path(".seethrough")
GOALS = DIR / "goals.json"
LEDGER = DIR / "ledger.jsonl"


def now():
    return datetime.now(timezone.utc).isoformat()


def log(event, **kw):
    DIR.mkdir(exist_ok=True)
    with open(LEDGER, "a", encoding="utf-8") as f:
        f.write(json.dumps({"ts": now(), "event": event, **kw}, ensure_ascii=False) + "\n")


def load():
    if not GOALS.exists():
        sys.exit("seethrough: no plan — run `create` from the repo root first.")
    return json.loads(GOALS.read_text(encoding="utf-8"))


def save(plan):
    DIR.mkdir(exist_ok=True)
    GOALS.write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")


def cmd_create(a):
    if GOALS.exists() and not a.force:
        sys.exit("seethrough: a plan already exists. Check `status`, or replace with --force.")
    goals = []
    for i, g in enumerate(a.goal, 1):
        if "::" not in g:
            sys.exit(f"seethrough: --goal format is 'title::objective' — invalid: {g}")
        title, obj = g.split("::", 1)
        goals.append({"id": f"G{i:03d}", "title": title.strip(), "objective": obj.strip(),
                      "status": "pending", "evidence": None})
    if not goals:
        sys.exit("seethrough: at least one --goal is required.")
    save({"brief": a.brief, "created": now(), "goals": goals})
    log("plan_created", brief=a.brief, count=len(goals))
    print(f"seethrough: plan created — {len(goals)} stories")
    for g in goals:
        print(f"  {g['id']} {g['title']}: {g['objective']}")


def cmd_next(a):
    plan = load()
    active = [g for g in plan["goals"] if g["status"] == "in_progress"]
    if active:
        g = active[0]
    else:
        pending = [g for g in plan["goals"] if g["status"] == "pending"]
        if not pending:
            print("seethrough: all stories complete ✓"); return
        g = pending[0]
        g["status"] = "in_progress"
        save(plan); log("story_started", id=g["id"], title=g["title"])
    is_final = g["id"] == plan["goals"][-1]["id"]
    print(f"=== seethrough handoff — {g['id']} {g['title']}")
    print(f"Objective: {g['objective']}")
    print("Rule: work this story only. Produce evidence as you go.")
    if is_final:
        print("★ Final story — `complete` requires --verify-cmd and --verify-evidence (verification gate).")
    print(f"On completion: goals.py checkpoint --id {g['id']} --status complete --evidence \"<evidence>\""
          + (" --verify-cmd \"<command>\" --verify-evidence \"<result>\"" if is_final else ""))


def cmd_checkpoint(a):
    plan = load()
    g = next((x for x in plan["goals"] if x["id"] == a.id), None)
    if not g:
        sys.exit(f"seethrough: {a.id} not found.")
    if g["status"] != "in_progress":
        sys.exit(f"seethrough: {a.id} is not active ({g['status']}) — activate it with `next` first.")
    if a.status == "complete":
        if not (a.evidence and a.evidence.strip()):
            sys.exit("seethrough: a complete checkpoint requires non-empty --evidence.")
        if g["id"] == plan["goals"][-1]["id"]:
            if not (a.verify_cmd and a.verify_cmd.strip() and a.verify_evidence and a.verify_evidence.strip()):
                sys.exit("seethrough: the final story cannot complete without --verify-cmd and --verify-evidence.")
    g["status"] = a.status
    g["evidence"] = a.evidence
    save(plan)
    log("checkpoint", id=g["id"], status=a.status, evidence=a.evidence,
        verify_cmd=a.verify_cmd, verify_evidence=a.verify_evidence)
    print(f"seethrough: {g['id']} → {a.status}")
    remaining = [x for x in plan["goals"] if x["status"] in ("pending", "in_progress")]
    print("seethrough: all stories complete ✓" if not remaining
          else f"seethrough: {len(remaining)} stories left — continue with `next`.")


def cmd_status(a):
    plan = load()
    done = sum(1 for g in plan["goals"] if g["status"] == "complete")
    print(f"seethrough: {done}/{len(plan['goals'])} complete — {plan['brief']}")
    mark = {"complete": "✓", "in_progress": "▶", "pending": "·", "failed": "✗", "blocked": "■"}
    for g in plan["goals"]:
        print(f"  {mark.get(g['status'], '?')} {g['id']} [{g['status']}] {g['title']}")


def main():
    p = argparse.ArgumentParser(prog="goals.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create"); c.add_argument("--brief", required=True)
    c.add_argument("--goal", action="append", default=[]); c.add_argument("--force", action="store_true")
    sub.add_parser("next")
    k = sub.add_parser("checkpoint"); k.add_argument("--id", required=True)
    k.add_argument("--status", required=True, choices=["complete", "failed", "blocked"])
    k.add_argument("--evidence", default=""); k.add_argument("--verify-cmd", dest="verify_cmd", default="")
    k.add_argument("--verify-evidence", dest="verify_evidence", default="")
    sub.add_parser("status")
    a = p.parse_args()
    {"create": cmd_create, "next": cmd_next, "checkpoint": cmd_checkpoint, "status": cmd_status}[a.cmd](a)


if __name__ == "__main__":
    main()
```

### 6.10 `skills/seethrough/SKILL.md`

**역할:** 스킬 진입점. 태스크가 description과 매칭될 때 모델이 호출해 전체 규율을 오케스트레이션한다.
**참조 내용:**

```markdown
---
name: seethrough
description: A harness that enforces seeing a task through to the end, with evidence and verification, as procedure. Use when starting a multi-step task (2+ sequential stories), long autonomous work, debugging or root-cause investigation, building render/executable artifacts (HTML, SVG, games, charts), or when the user says "seethrough", "see it through", "verify as you go", "split into goals".
---

# seethrough — 끝까지, 증거와 함께

> 원칙: 하네스는 모델의 천장을 못 올린다. 모델이 자기 천장까지 가도록 — 검증·완료·조사를 절차로 강제할 뿐이다. 천장(열린 창의성, 사양 밖 발견)이 막으면 escalate한다(§4).
> 태스크가 보내는 신호에 해당하는 규율만 적용한다(가장 작은 매칭 규율; 진짜 멀티카테고리일 때만 중첩). 상시 설치(always-on)되면 라우팅은 자동이다.

## 0. 첫 실행 — 자동 온보딩(1회)

요청 작업 전에, 이 머신에 온보딩됐는지 확인:

```bash
cat ~/.seethrough/progress.json 2>/dev/null
```

- 파일이 **있으면** — 온보딩 생략, 바로 작업.
- **없으면** — 단일 AskUserQuestion으로 1회 온보딩. **질문/옵션은 사용자의 현재 대화 언어로** 표현한다.
  - 질문(의미): "seethrough를 설정할까요?"
  - 옵션(의미): "Local — 이 프로젝트만(권장)" / "Global — 모든 프로젝트" / "Skip".
  - Local/Global 선택 시:
    ```bash
    bash ${CLAUDE_PLUGIN_ROOT}/setup/setup.sh <local|global>
    ```
  - Skip 선택 시(다시 묻지 않도록 기록):
    ```bash
    mkdir -p ~/.seethrough && printf '{"setup_done":false,"skipped":true}' > ~/.seethrough/progress.json
    ```

## 1. 멀티스토리 루프 (2개 이상 순차 스토리)

순차 스토리로 분해하고 하나씩 완료하며 증거를 남긴다. 저장소 루트에서 실행하고 상태는 `./.seethrough/`에 영속(세션 넘어 `status`로 복구).

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/goals.py create --brief "<요약>" \
  --goal "제목::검증 가능한 목표" --goal "제목::..."   # 마지막 목표는 검증 스토리
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/goals.py next
# ... 그 스토리만 작업 ...
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/goals.py checkpoint --id G001 --status complete --evidence "<구체적 증거>"
# 마지막 스토리는 검증 게이트: --verify-cmd "<명령>" --verify-evidence "<결과>" 필수
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/goals.py status
```

규칙: `complete`는 비어있지 않은 증거 필수; 마지막 목표는 verify 명령과 결과 없이 완료 불가(엔진이 거부). 막히면 `--status blocked`로 기록 후 보고. 단일 스텝 작업은 이 루프를 건너뛴다.

## 2. 심층 조사 (디버깅 / 미상 원인 / 리뷰)

`${CLAUDE_PLUGIN_ROOT}/packs/investigation-protocol.md`를 읽고 따른다: 재현 먼저 → 3+ 경쟁 가설 → 가설별 증거 → 전체 인과 사슬 → 전후 검증 → 기각 가설 보고.

## 3. 검증 그라운딩 (렌더/실행 산출물 — 항상)

`${CLAUDE_PLUGIN_ROOT}/packs/verification-grounding.md`를 따른다: 실제 렌더러 실행 → 실제 출력 관찰 → 관찰이 드러낸 것 수정 → 재실행. 정적 파싱은 well-formed 확인이지 correct 확인이 아니다.

## 3-1. 작업 방식 (항상)

결과부터 말한다. 요청 범위 안에 머문다(곁다리 리팩터/추상화 금지). 모든 완료 주장을 이번 세션의 도구 실행 결과에 묶는다. 파괴적/되돌리기 어려운 작업 전에는 확인받는다.

## 4. 능력 천장에서 (escalate)

천장 신호: 같은 문제에 2회+ 막힘; 디테일 자체가 가치인 열린 창작; 사양 밖 발견이 필요한 심층 리뷰. 이는 절차가 아니라 능력이라 하네스가 못 메운다. 순서대로: (1) 사용자에게 `/effort xhigh`를 권해 현재 모델을 천장까지 밀기; (2) 그래도 부족하면 증거 패키지(증상·시도·실패 지점·재현)와 함께 더 센 모델의 새 세션으로 핸드오프; (3) 그것도 아니면 한계를 솔직히 보고하고 사람이 개입할 지점을 명시.
```

### 6.11 `setup/operating-block.md`

**역할:** CLAUDE.md에 주입할 상시 운영 블록 템플릿. 주입되면 매 세션 상주(soft·항상).
**규칙:** `__PLUGIN_ROOT__`는 setup.sh가 실제 경로로 치환. `<!-- SEETHROUGH:BEGIN ... -->` / `<!-- SEETHROUGH:END -->` 마커로 감싼다(멱등 주입/제거용).
**참조 내용:**

```markdown
<!-- SEETHROUGH:BEGIN — 끝까지, 증거와 함께 (always-on). 검증된 절차만. 설치/갱신: setup.sh -->
## 운영 모드 (상시 — 태스크 신호로 자동 라우팅)

태스크 신호에 해당하는 것만 적용한다. 신호가 없으면 baseline만. 각 팩은 필요할 때만 읽는다.

- **[항상]** 결과부터 말한다 · 요청 범위 안에 머문다(곁다리 리팩터 금지) · 완료 주장을 이번 세션의 도구 결과에 묶는다 · 파괴적/되돌리기 어려운 작업 전 확인.
- **[2+ 순차 스토리]** `python3 __PLUGIN_ROOT__/scripts/goals.py` 실행: create → next → checkpoint(증거 동반) → 마지막 검증 게이트(`--verify-cmd`/`--verify-evidence` 없이 완료 불가). 저장소 루트에서 실행, 상태는 `./.seethrough/`(복구는 `status`). 단일 스텝은 생략.
- **[디버깅 / 테스트 실패 / 미상 원인 / 리뷰]** `__PLUGIN_ROOT__/packs/investigation-protocol.md`: 재현 먼저 → 3+ 경쟁 가설 → 가설별 증거 → 전체 인과 사슬 → 전후 검증 → 기각 가설 보고.
- **[렌더/실행 산출물: HTML, SVG, 게임, UI, 차트]** `__PLUGIN_ROOT__/packs/verification-grounding.md` 그라운딩 루프: 실제 렌더러 실행 → 출력 관찰 → 본 것 수정 → 재실행. 정적 검사는 관찰이 아니다.
- **[어렵거나 모호한 태스크]** 막히면(2회+) 또는 사양 밖 발견이 필요하면 한계를 솔직히 보고하고 escalate. 깊이(능력)는 못 올린다. 더 높이려면 사용자에게 `/effort xhigh`를 권한다.
<!-- SEETHROUGH:END -->
```

### 6.12 `setup/setup.sh`

**역할:** 상시 적용 설치. 운영 블록을 CLAUDE.md에 멱등 주입하고 상태를 기록한다. **star 없음.**
**호출 시점:** 사용자가 1회 실행, 또는 스킬 첫 실행 온보딩.
**동작 계약:** CLAUDE.md 백업 → 기존 마커 제거 → `__PLUGIN_ROOT__` 치환 후 재주입 → `~/.seethrough/progress.json` 기록. settings.json은 건드리지 않는다(훅은 hooks.json으로 자동 등록되므로).
**참조 구현:**

```bash
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
```

### 6.13 `setup/uninstall.sh`

**역할:** CLAUDE.md에서 운영 블록을 멱등 제거.
**참조 구현:**

```bash
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
```

### 6.14 `commands/setup.md`

**역할:** `/seethrough:setup` 슬래시 커맨드 정의. (star 질문 없음 — 설치만.)
**참조 내용:**

```markdown
---
description: Set up seethrough always-on (inject the operating block into CLAUDE.md).
---

seethrough 설정을 실행한다. 1회만, 앞에서 묻는다.

## Step 1 — 설치 여부/범위를 묻는다 (질문 1회)

AskUserQuestion 사용. **질문/옵션은 사용자의 현재 대화 언어로** 표현한다.
- 질문(의미): "seethrough를 설정할까요?"
- 옵션(의미): 1) "Local — 이 프로젝트만(권장)"  2) "Global — 모든 프로젝트"  3) "취소"

"취소"면 아무것도 하지 않고 멈춘다.

## Step 2 — 설치 실행

"Local"/"Global"이면:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/setup/setup.sh <local|global>
```

setup.sh는 CLAUDE.md를 백업하고 `<!-- SEETHROUGH -->` 블록을 주입한 뒤 `~/.seethrough/progress.json`을 기록한다. 결과를 간단히 보고한다.
```

### 6.15 `.gitignore`

```
__pycache__/
*.pyc
*.seethrough-bak.*
.DS_Store
.seethrough/
```

### 6.16 `README.md`

**역할:** 사람용 문서. 목적·철학·무엇이 전이되고 안 되는지·설치/제거·정직한 한계. 과장하지 말고 "하네스는 천장을 못 올린다, star 자동화는 없다"를 명시. (분량 자유. 위 §1·§2 내용을 사람이 읽기 좋게 풀어 쓰면 된다.)

---

## 7. 빌드 순서 (이 순서로 구현)

1. **디렉터리·매니페스트 골격**: 파일 트리 생성, `plugin.json`, `.gitignore`.
2. **결정론 코어 먼저(테스트 가능)**: `scripts/goals.py` → `hooks/router.py` + `router-rules.json` → `hooks/finish-the-work.py`. 각 파일 작성 직후 §8의 해당 단위 테스트로 검증.
3. **훅 등록**: `hooks/hooks.json` (router + finish-the-work 둘 다).
4. **soft 자산**: `packs/*.md`, `skills/seethrough/SKILL.md`, `setup/operating-block.md`.
5. **설치 도구**: `setup/setup.sh`, `setup/uninstall.sh`, `commands/setup.md`. 작성 후 §8 설치 멱등성 테스트.
6. **문서**: `README.md`.
7. **통합 스모크 테스트**(§8) 전부 통과 확인.

---

## 8. 테스트 계획 (수용 전 반드시 통과)

훅은 stdin→stdout 계약이라 모델 없이 가짜 JSON으로 단위 테스트가 된다. **아래를 실제로 실행해 출력을 확인**한다(정적 검토로 대체하지 않는다 — 우리 철학 그대로).

**router.py — 매칭 시 주입, 비매칭 시 침묵, 항상 exit 0**
```bash
echo '{"prompt":"please help me debug this crash"}' | python3 hooks/router.py    # → investigation 안내 출력
echo '{"prompt":"build an svg chart"}'              | python3 hooks/router.py    # → grounding 안내 출력
echo '{"prompt":"refactor my error handling docs"}' | python3 hooks/router.py    # → (단어경계) "error" 단독 단어면 매칭됨에 유의; 의도된 동작 확인
echo '{"prompt":"write a haiku"}'                   | python3 hooks/router.py; echo "exit=$?"   # → 출력 없음, exit=0
echo 'not json'                                     | python3 hooks/router.py; echo "exit=$?"   # → 출력 없음, exit=0
```

**finish-the-work.py — 약속만 하면 block, 질문/도구호출/과거형이면 통과, loop guard 동작**
```bash
# 가짜 transcript 생성
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"좋습니다. 이제 로그인 폼을 구현하겠습니다."}]}}' > /tmp/t1.jsonl
echo "{\"transcript_path\":\"/tmp/t1.jsonl\",\"stop_hook_active\":false}" | python3 hooks/finish-the-work.py    # → {"decision":"block",...}

printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"로그인 폼을 구현했습니다. 더 진행할까요?"}]}}' > /tmp/t2.jsonl
echo "{\"transcript_path\":\"/tmp/t2.jsonl\",\"stop_hook_active\":false}" | python3 hooks/finish-the-work.py; echo "exit=$?"  # → 출력 없음(질문으로 끝남), exit=0

# loop guard: 같은 약속이어도 stop_hook_active=true면 통과
echo "{\"transcript_path\":\"/tmp/t1.jsonl\",\"stop_hook_active\":true}" | python3 hooks/finish-the-work.py; echo "exit=$?"   # → 출력 없음, exit=0
```

**goals.py — 증거/검증 게이트가 실제로 거부하는가**
```bash
cd "$(mktemp -d)"   # 임시 저장소 루트
python3 /path/to/scripts/goals.py create --brief "demo" --goal "impl::로그인 구현" --goal "verify::테스트 통과 확인"
python3 /path/to/scripts/goals.py next
python3 /path/to/scripts/goals.py checkpoint --id G001 --status complete --evidence ""   # → 거부(증거 없음)로 비정상 종료
python3 /path/to/scripts/goals.py checkpoint --id G001 --status complete --evidence "폼 컴포넌트 + 핸들러 커밋 abc123"   # → 성공
python3 /path/to/scripts/goals.py next
python3 /path/to/scripts/goals.py checkpoint --id G002 --status complete --evidence "테스트 추가"   # → 거부(마지막 스토리, verify 누락)
python3 /path/to/scripts/goals.py checkpoint --id G002 --status complete --evidence "테스트 추가" --verify-cmd "npm test" --verify-evidence "12 passed, 0 failed"   # → 성공
python3 /path/to/scripts/goals.py status   # → 2/2 complete
```

**setup.sh / uninstall.sh — 멱등성**
```bash
cd "$(mktemp -d)"; export CLAUDE_PLUGIN_ROOT=/path/to/seethrough
bash "$CLAUDE_PLUGIN_ROOT/setup/setup.sh" local   # CLAUDE.md에 블록 1개 주입 + 백업 생성
bash "$CLAUDE_PLUGIN_ROOT/setup/setup.sh" local   # 다시 실행해도 블록은 여전히 1개여야 함(중복 금지)
grep -c "SEETHROUGH:BEGIN" CLAUDE.md              # → 1
bash "$CLAUDE_PLUGIN_ROOT/setup/uninstall.sh" local
grep -c "SEETHROUGH:BEGIN" CLAUDE.md              # → 0
```

**통합 스모크**: 실제 VSCode Claude Code에서 `/plugin marketplace add <local path>` → `/plugin install seethrough` → 디버깅 프롬프트를 주고 라우터 안내가 컨텍스트에 뜨는지, "이제 ~하겠습니다"로만 끝낼 때 finish-the-work가 재engage하는지 확인.

---

## 9. 수용 기준 (체크리스트)

- [ ] `hooks/hooks.json`에 **router(UserPromptSubmit)와 finish-the-work(Stop)가 둘 다** 등록돼 있다.
- [ ] 라우터 키워드 매핑이 코드가 아니라 `router-rules.json`에 있고, 항목 추가만으로 규율을 늘릴 수 있다.
- [ ] 라우터는 ascii 키워드에 **단어 경계 매칭**을 쓰고, 매칭 없으면 침묵하며, **어떤 입력에도 exit 0**이다.
- [ ] finish-the-work는 `stop_hook_active=true`면 즉시 통과(무한 루프 없음), 도구호출/무텍스트/질문-종료면 통과, 약속-종료면 `{"decision":"block"}`을 낸다.
- [ ] goals.py: `complete`는 증거 없이 거부, **마지막 스토리는 verify-cmd+verify-evidence 없이 거부**, 상태가 `./.seethrough/`에 영속된다.
- [ ] setup.sh는 백업을 만들고 **멱등**(두 번 실행해도 블록 1개)이며, uninstall.sh가 깨끗이 제거한다. **settings.json은 건드리지 않는다.**
- [ ] **GitHub star 관련 코드·질문·파일이 어디에도 없다.**
- [ ] §8의 모든 명령을 실제로 실행해 기대 출력을 확인했다(정적 검토로 대체하지 않음).
- [ ] 플러그인 이름이 모든 파일에서 일관된다(`seethrough` 또는 사용자가 바꾼 이름).
```
