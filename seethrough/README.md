# seethrough

> 끝까지, 증거와 함께. — A Claude Code plugin that enforces **completion, evidence, and verification as procedure**.

`seethrough`는 LLM 코딩 에이전트의 **능력(capability)이 아니라 규율(discipline)의 실패**를 막는 하네스다. 모델이 "할 수 없어서"가 아니라 "안 해서" 건너뛰는 절차들을 호스트가 기계적으로 강제한다:

- 실행해보지 않고 완료 선언
- 약속만 하고 턴 종료 ("이제 ~하겠습니다")
- 증상만 고친 버그 수정
- 긴 작업 중 진행 상황 분실

## 핵심 원칙

> **모델의 선의에 맡기지 말고, 기계적으로 판정 가능한 규율은 결정론적 관문(gate)으로 강제한다. 판정 불가능한 규율만 컨텍스트 주입(soft)으로 안내하되, 관련 있을 때만 주입한다.**

비유: "배포 전에 테스트 꼭 돌려"라고 말로 부탁하는 것(soft)과, 테스트가 초록불이 아니면 머지가 안 되는 CI 게이트(hard)의 차이. 가장 자주·치명적으로 빠뜨리는 규율일수록 hard 쪽에 둔다.

## 정직한 한계 (과장하지 않음)

- **하네스는 모델의 천장을 올리지 않는다.** 모델이 자기 천장까지 가도록 만들 뿐이다. 열린 창의성이나 사양 밖 발견이 필요한 지점에서는 솔직히 한계를 보고하고 escalate하도록 안내한다(자동으로 더 똑똑해지지 않는다).

## 무엇이 hard이고 무엇이 soft인가

| 규율                           | 표면                                   | 종류                  | 동작                                                                                                        |
| ------------------------------ | -------------------------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------- |
| 조기 종료(약속만 하고 끝) 차단 | `Stop` 훅 (`finish-the-work.py`)       | **hard**              | 약속형 종료면 `{"decision":"block"}`으로 재engage. `stop_hook_active`로 무한 루프 방지.                     |
| 멀티스토리 증거/검증 게이트    | `scripts/goals.py`                     | **hard**              | `complete`엔 증거 필수, 마지막 스토리엔 verify 명령+결과 필수. 없으면 거부. 상태는 `./.seethrough/`에 영속. |
| 퍼-태스크 라우팅               | `UserPromptSubmit` 훅 (`router.py`)    | hard(전달)+soft(내용) | 프롬프트 신호를 단어 경계로 매칭해 관련 팩 안내만 주입. 매칭 없으면 침묵, 항상 exit 0.                      |
| 조사 프로토콜(디버깅)          | `packs/investigation-protocol.md`      | **soft**              | 재현 먼저 → 3+ 경쟁 가설 → 가설별 증거 → 전체 인과 사슬 → 전후 검증 → 기각 가설 보고.                       |
| 검증 그라운딩(렌더 산출물)     | `packs/verification-grounding.md`      | **soft**              | 실제 렌더러 실행 → 출력 관찰 → 본 것 수정 → 재실행. well-formed ≠ correct.                                  |
| baseline 운영 규율             | `setup/operating-block.md` → CLAUDE.md | **soft(상주)**        | 결과부터 · 범위 안에 머물기 · 완료를 도구 결과에 묶기 · 파괴적 작업 전 확인.                                |

라우터 규칙은 코드가 아니라 데이터(`hooks/router-rules.json`)에 있다. **새 규율 추가 = 항목 한 줄 추가.**

## 설치

1. **GitHub에서 설치 (공개):**

   ```
   /plugin marketplace add ehdrms785/seethrough
   /plugin install seethrough@daro
   ```

   또는 개발 중이면 로컬 경로로:

   ```
   /plugin marketplace add /path/to/seethrough
   /plugin install seethrough@daro
   ```

   설치되면 훅(router + finish-the-work)이 `hooks/hooks.json`으로 **자동 등록**된다.

2. (선택) 상시 운영 블록을 CLAUDE.md에 주입 — `/seethrough:setup` 또는:
   ```bash
   bash setup/setup.sh local    # 이 프로젝트만 (권장)
   bash setup/setup.sh global   # 모든 프로젝트
   ```
   멱등(여러 번 실행해도 블록 1개), 백업 생성, `settings.json`은 건드리지 않는다.

## 제거

```bash
bash setup/uninstall.sh local    # 또는 global
```

CLAUDE.md에서 `<!-- SEETHROUGH -->` 블록만 깨끗이 제거한다(원본 내용 보존, 백업은 수동 삭제). 훅은 플러그인 제거 시 자동으로 빠진다.

## 검증

루트의 `verify.sh`(저장소 동봉)가 결정론적 수용 게이트다 — router/finish-the-work/goals/setup의 동작 계약을 stdin/stdout으로 검사하고, 전부 통과하면 `✓ ALL GREEN` 후 exit 0, 하나라도 실패하면 exit 1.

```bash
bash verify.sh
```

## 파일 구조

```
seethrough/
├── .claude-plugin/{plugin,marketplace}.json   # 매니페스트
├── hooks/                                       # router(+rules) + finish-the-work + hooks.json
├── packs/                                        # soft 규율 (investigation, grounding)
├── scripts/goals.py                              # hard 멀티스토리 검증 게이트
├── skills/seethrough/SKILL.md                    # 스킬 진입점·오케스트레이션
├── setup/                                        # operating-block + 멱등 setup/uninstall
├── commands/setup.md                             # /seethrough:setup
└── README.md
```

런타임 상태(`./.seethrough/`)와 백업(`*.seethrough-bak.*`)은 git에서 제외된다.
