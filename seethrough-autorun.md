# `seethrough` — 무인 빌드 + 검증 런북 (Auto Mode, 논스톱)

이 문서는 `seethrough-build-spec.md`로 플러그인을 **멈춤 없이 빌드하고 다양한 카테고리로 검증**까지 한 번에 돌리는 방법이다. 동봉된 `verify.sh`는 그 무인 루프가 "끝났다"를 판단하는 **결정론적 완료 신호**다(정상 트리에서 16/16 통과, 회귀 시 비정상 종료가 실측 검증됨).

---

## 0. 핵심 개념: "논스톱"은 두 가지가 맞물려야 성립한다

1. **권한 모드** — Claude Code가 도구 호출(파일 쓰기/bash)마다 사람에게 승인을 묻지 않아야 한다. (아래 §1)
2. **결정론적 완료 신호** — "언제 멈춰도 되는가"를 모델 판단이 아니라 `verify.sh`의 종료 코드로 정한다. 루프는 "verify.sh가 0을 반환할 때까지" 자기수정하며 돈다. (아래 §3·§4)

이 둘이 없으면 "논스톱"은 (1) 승인 대기에서 멈추거나 (2) 모델이 "다 된 것 같다"며 조기 종료한다. (2)는 마침 이 플러그인의 `finish-the-work` 훅이 막는 문제이기도 하다 — 단, 빌드 단계에선 플러그인이 아직 설치 전이므로 (1)은 권한 모드로, (2)는 아래 킥오프 프롬프트로 막는다.

---

## 1. 권한 모드 선택 (현재 Claude Code 사양 기준)

Claude Code의 권한 모드는 `default`, `acceptEdits`, `bypassPermissions`, `dontAsk`, `plan`, `auto` 6가지다. 무인 실행 관점에서 정리:

| 모드 | 동작 | 무인 적합성 | 비고 |
|---|---|---|---|
| `default` | bash·중요 쓰기마다 승인 질문 | ✗ | 매번 멈춤 |
| `acceptEdits` | 파일 편집 자동 승인, bash는 질문 | △ | 편집은 흐르나 명령마다 멈춤 |
| `auto` | Anthropic의 분류기 기반 "안전한 권한 스킵" | ◎ (권장) | 위험 행동만 차단·백스톱 있음 |
| `bypassPermissions` / `--dangerously-skip-permissions` | 모든 권한 검사 스킵 (YOLO) | ○ (격리 필수) | 첫 실행 시 1회 대화형 확인 |
| `dontAsk` | 비대화형에서 질문 없이 진행 | ○ (스크립트/CI용) | 헤드리스에 적합 |
| `plan` | 실행 없이 계획만 | ✗ | 무인 빌드엔 부적합 |

핵심 사실:
- `--dangerously-skip-permissions`는 Anthropic이 "Safe YOLO mode"라 부르는 **완전 무인 실행**으로, 권한 프롬프트를 전부 우회한다. 단 **첫 실행 시 1회 대화형 확인 다이얼로그가 떠서 거기서 멈춘다.** 진짜 비대화형(스크립트/TTY 없음)에는 `--permission-mode dontAsk`를 써야 그 다이얼로그 없이 동작한다.
- `auto` 모드는 더 안전한 대안이다. 트랜스크립트 분류기가 위험 행동을 차단하고, **연속 3회 또는 누적 20회 거부가 쌓이면 모델을 멈추고 사람에게 에스컬레이션**한다. 헤드리스(`claude -p`)엔 UI가 없으므로 그 경우 프로세스를 종료한다. 즉 `auto`의 "논스톱"은 무한이 아니라 안전 천장이 있다(이게 폭주 방지 기능이다).
- 대화형 세션에서는 `Shift+Tab`으로 `default → acceptEdits → plan`을 순환하고, 계정이 자격을 갖추면 `auto`가, `--allow-dangerously-skip-permissions`로 시작하면 `bypassPermissions`가 순환에 추가된다. 상태바에 현재 모드가 표시된다.
- 안전장치: `bypassPermissions`는 Linux/macOS에서 **root/sudo로는 시작을 거부**하며, 인식된 샌드박스 안에서는 그 검사를 건너뛴다. 컨테이너에서 자율 실행하려면 dev container 구성(비root 사용자로 실행)을 쓴다.

### 권장 선택

- **본인 개발 머신(VSCode)에서 곁눈질하며**: `auto` 모드. VSCode에서 `Shift+Tab`으로 `auto`로 순환(계정 자격이 있으면 노출, 첫 진입 시 옵트인). 분류기 백스톱이 폭주를 막아준다.
- **밤새 완전 무인으로 돌리려면**: **격리된 컨테이너 + 헤드리스**. `claude -p "<킥오프>" --permission-mode dontAsk --output-format stream-json`. 컨테이너 경계가 보안을 담당하므로 권한 프롬프트는 마찰만 더한다.
- 절대 인터넷 연결된 메인 머신에서 `bypassPermissions`를 켜지 말 것 — 프롬프트 인젝션(악성 README/주석/설정이 무승인 셸 실행을 유발) 위험. 무인 실행은 격리가 선택이 아니라 전제다.

---

## 2. 격리 (무인 실행의 전제)

훅은 샌드박스 없이 사용자 권한으로 돈다. 자동 승인 + 임의 셸 실행 조합은 반드시 격리한다. 최소 한 가지:

- **dev container / Docker**: 자격증명 미주입, 외부 네트워크 차단. dev container 구성은 Claude Code를 비root로 실행해 bypass 모드의 root 거부도 우회한다.
- **그게 어려우면 최소한**: 전용 작업 디렉터리 + git 초기 커밋(체크포인트) + 위험 명령 deny 룰을 `settings.json`에 커밋(예: `rm -rf`, 외부 푸시 등 차단). 영속 deny 룰이 CLI 플래그를 외우는 것보다 신뢰성 높다.

---

## 3. 검증 게이트 `verify.sh` (동봉, 실측 통과)

플러그인 저장소 루트에 둔다. 모델 없이 stdin/stdout 계약으로 핵심을 결정론적으로 검사한다:

- router: 디버그/렌더 신호 주입, 무신호 침묵, 잘못된 JSON에도 exit 0
- finish-the-work: 약속만→block, loop guard→통과, 질문 종료→통과
- goals.py: 증거 없는 완료 거부, 마지막 스토리 verify 누락 거부
- setup.sh: 멱등(2회 실행 후 블록 1개)·원본 보존·uninstall 제거
- star 코드 부재(플러그인 소스 한정 스캔)

**사용**: `bash verify.sh` → 전부 통과 시 `✓ ALL GREEN` 출력 후 exit 0, 하나라도 실패하면 실패 목록 출력 후 exit 1. **이 종료 코드가 무인 루프의 종료 조건이다.** (네거티브 컨트롤로, 게이트를 일부러 무력화하면 verify.sh가 exit 1로 잡아냄을 확인했다 — 도장 찍기가 아니다.)

> 새 라우터 규칙이나 새 팩을 추가하면 `verify.sh`에 대응 어서션 한 줄을 같이 추가한다. 게이트가 신규 기능을 덮지 못하면 "초록불"이 거짓이 된다.

---

## 4. 카테고리 행동 검증 `category-eval.sh` (헤드리스, 환경 의존)

`verify.sh`가 "코드가 맞게 동작하는가"(결정론)라면, 이건 "설치된 플러그인이 실제 Claude Code 세션에서 다양한 요청에 의도대로 반응하는가"(통합·행동)를 본다. **이 계층은 라이브 모델이라 노이즈가 있다** — 강한 신호(파일·종료코드)만 어서션하고, 약한 신호(서술)는 로그로 남겨 사람이 본다.

```bash
#!/usr/bin/env bash
# category-eval.sh — 설치된 seethrough 플러그인을 다양한 카테고리로 헤드리스 구동.
# 전제: 이 환경에 `claude` CLI가 있고 seethrough 플러그인이 설치됨. 격리된 컨테이너 권장.
set -uo pipefail
CLAUDE="${CLAUDE_BIN:-claude}"
MODE="${PERM_MODE:---permission-mode dontAsk}"   # 비대화형
RUN() { # RUN "<dir>" "<prompt>"
  d="$1"; shift; mkdir -p "$d"; ( cd "$d" && git init -q 2>/dev/null
    timeout 900 $CLAUDE -p "$*" $MODE --output-format stream-json > run.jsonl 2>&1 )
}
root="$(mktemp -d)"; cd "$root"; fail=0
chk(){ if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=$((fail+1)); fi; }

# 1) 멀티스토리(코드 생성): 게이트가 작동하면 ./.seethrough/goals.json 생성 + 마지막 verify 증거
RUN c1 "두 개의 순차 작업으로 진행해줘: (1) JS로 add(a,b) 모듈 작성 (2) 테스트로 검증. seethrough 멀티스토리 루프를 사용하고, 마지막 스토리는 검증 게이트로 닫아줘."
chk "multi-story → goals.json 생성"        "[ -f c1/.seethrough/goals.json ]"
chk "multi-story → ledger에 verify 기록"   "grep -q verify_cmd c1/.seethrough/ledger.jsonl"

# 2) 렌더 산출물: 그라운딩 루프가 돌면 실제 렌더 산출물(스크린샷/PNG 등)이 남아야 함
RUN c2 "간단한 SVG 막대 차트를 만들고, 완료 선언 전에 실제로 렌더해서 출력을 직접 관찰한 뒤 결과를 알려줘."
chk "render → 산출물 파일 존재"            "ls c2/*.svg c2/*.png c2/*.html >/dev/null 2>&1"
chk "render → 관찰(스크린샷/렌더) 흔적"     "grep -qiE 'screenshot|render|관찰|observed' c2/run.jsonl"

# 3) 디버깅(소프트 신호): 조사 프로토콜 흔적
RUN c3 "이 코드는 가끔 null을 반환해 크래시한다고 가정하고 디버깅해줘: function f(x){return x.v}. 재현부터 시작해줘."
chk "debug → 가설/재현 서술(소프트)"        "grep -qiE 'reproduce|hypothes|가설|재현' c3/run.jsonl"

# 4) 단일 스텝: 게이트 루프를 강요하지 않아야 함(과적용 방지)
RUN c4 "문자열을 뒤집는 한 줄짜리 JS 함수만 알려줘."
chk "single-step → goals 루프 미생성"       "[ ! -d c4/.seethrough ]"

echo "----"; [ "$fail" -eq 0 ] && echo "✓ category-eval GREEN" || { echo "✗ $fail 실패 — run.jsonl 확인"; exit 1; }
```

> 약한 어서션(grep 서술)은 모델 표현에 따라 흔들릴 수 있다. 실패해도 곧장 회귀로 단정하지 말고 `run.jsonl`을 사람이 확인한다. 강한 어서션(파일 존재/구조)이 핵심 신호다.

---

## 5. 무인 루프 오케스트레이션

빌드와 검증을 한 번에, 멈춤 없이. 두 가지 방식 중 택일.

### 방식 A — 헤드리스 셸 루프 (완전 무인, 컨테이너 권장)

```bash
#!/usr/bin/env bash
# autorun.sh — 컨테이너 안에서. 빌드→검증→자기수정을 verify.sh가 초록이 될 때까지 반복.
set -uo pipefail
MAX=6
for i in $(seq 1 $MAX); do
  echo "=== iteration $i ==="
  claude -p "$(cat KICKOFF.md)" --permission-mode dontAsk --output-format stream-json | tee iter_$i.jsonl
  if bash verify.sh; then echo "✓ DONE at iteration $i"; exit 0; fi
  echo "verify 실패 → 다음 반복에서 자기수정"
done
echo "✗ $MAX회 내 미완료 — 사람이 확인"; exit 1
```

`KICKOFF.md`(아래 §6)가 매 반복의 입력이다. 루프 자체가 "verify.sh가 0일 때까지"를 강제하므로, 모델이 중간에 "다 된 것 같다"고 해도 셸 루프가 검증으로 되돌린다.

### 방식 B — VSCode 인터랙티브 (곁눈질, auto 모드)

VSCode에서 `Shift+Tab`으로 `auto` 모드 진입 후, §6 킥오프 프롬프트를 그대로 붙여넣는다. 플러그인이 일단 설치·활성화되면 `finish-the-work` 훅이 조기 종료를 막아 논스톱을 보강한다. `auto`의 분류기 백스톱(연속 3·누적 20 거부 시 정지·에스컬레이션)이 폭주를 막는다.

---

## 6. 킥오프 프롬프트 (`KICKOFF.md`)

곡해 없이, "완료"의 정의와 논스톱 규율을 박아 넣는다.

```text
첨부한 seethrough-build-spec.md 를 그대로 구현한다. 다음을 논스톱으로 수행하라.

[빌드] §7 빌드 순서를 따라 모든 파일을 생성한다. 결정론 코어(router.py, router-rules.json,
finish-the-work.py, goals.py)와 setup 스크립트는 명세의 참조 구현을 기준으로 하되,
동작 계약(입출력·exit code·게이트 규칙)을 바꾸지 않는다.

[검증] 각 파일을 만든 직후 해당 단위 테스트를 실제로 실행해 출력을 직접 확인한다(정적 검토로 때우지 않는다).
전체가 모이면 `bash verify.sh` 를 실행한다. 실패 항목이 있으면 원인을 조사·수정하고 다시 verify.sh 를
초록불(exit 0)이 될 때까지 반복한다.

[행동 검증] verify.sh 가 초록이면, 가능한 환경에서 category-eval.sh 를 실행해 멀티스토리/렌더/디버깅/
단일스텝 카테고리가 의도대로 동작하는지 확인한다. 강한 어서션(파일/구조)이 실패하면 수정 후 재검증한다.

[완료 정의] `bash verify.sh` 가 exit 0 이고 §9 수용 기준 체크리스트가 전부 충족되면 완료다.
완료 전에는 턴을 끝내지 말고 다음 할 일을 도구 호출로 즉시 실행한다. 사용자만 결정할 수 있는 사안에
막혔을 때만 질문하고 멈춘다. "이제 ~하겠습니다" 같은 약속만 하고 끝내지 않는다.

[한계] 같은 문제에 2회 막히면 시도·증상·실패 지점을 요약해 보고하고 에스컬레이션한다. 추측으로 게이트를
우회하거나 동작 계약을 바꿔 통과시키지 않는다.
```

---

## 7. 종합 순서 요약

1. 격리 준비(컨테이너 또는 전용 디렉터리 + git 체크포인트 + deny 룰). (§2)
2. `seethrough-build-spec.md`, `verify.sh`, `KICKOFF.md`를 작업 폴더에 둔다.
3. 권한 모드 결정: 곁눈질=`auto`(VSCode Shift+Tab) / 완전 무인=컨테이너+`--permission-mode dontAsk`. (§1)
4. 방식 A(셸 루프) 또는 방식 B(인터랙티브)로 킥오프. (§5)
5. 루프는 `verify.sh` exit 0 + 수용 기준 충족에서 종료. 미완 시 자기수정 반복, 천장에서 에스컬레이션.

> "논스톱"의 안전 천장: `auto`는 위험 행동 누적 시 정지·에스컬레이션하고 헤드리스에선 프로세스를 종료한다.
> 무한 루프가 아니라 폭주 방지가 내장돼 있다는 뜻이다. 무인 실행은 항상 격리 안에서.
