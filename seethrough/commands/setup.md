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
