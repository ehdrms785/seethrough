<!-- SEETHROUGH:BEGIN — 끝까지, 증거와 함께 (always-on). 검증된 절차만. 설치/갱신: setup.sh -->
## 운영 모드 (상시 — 태스크 신호로 자동 라우팅)

태스크 신호에 해당하는 것만 적용한다. 신호가 없으면 baseline만. 각 팩은 필요할 때만 읽는다.

- **[항상]** 결과부터 말한다 · 요청 범위 안에 머문다(곁다리 리팩터 금지) · 완료 주장을 이번 세션의 도구 결과에 묶는다 · 파괴적/되돌리기 어려운 작업 전 확인.
- **[2+ 순차 스토리]** `python3 __PLUGIN_ROOT__/scripts/goals.py` 실행: create → next → checkpoint(증거 동반) → 마지막 검증 게이트(`--verify-cmd`/`--verify-evidence` 없이 완료 불가). 저장소 루트에서 실행, 상태는 `./.seethrough/`(복구는 `status`). 단일 스텝은 생략.
- **[디버깅 / 테스트 실패 / 미상 원인 / 리뷰]** `__PLUGIN_ROOT__/packs/investigation-protocol.md`: 재현 먼저 → 3+ 경쟁 가설 → 가설별 증거 → 전체 인과 사슬 → 전후 검증 → 기각 가설 보고.
- **[렌더/실행 산출물: HTML, SVG, 게임, UI, 차트]** `__PLUGIN_ROOT__/packs/verification-grounding.md` 그라운딩 루프: 실제 렌더러 실행 → 출력 관찰 → 본 것 수정 → 재실행. 정적 검사는 관찰이 아니다.
- **[어렵거나 모호한 태스크]** 막히면(2회+) 또는 사양 밖 발견이 필요하면 한계를 솔직히 보고하고 escalate. 깊이(능력)는 못 올린다. 더 높이려면 사용자에게 `/effort xhigh`를 권한다.
<!-- SEETHROUGH:END -->
