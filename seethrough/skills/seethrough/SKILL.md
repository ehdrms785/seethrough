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
