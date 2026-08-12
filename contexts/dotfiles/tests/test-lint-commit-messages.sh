#!/usr/bin/env bash
# test-lint-commit-messages.sh
#
# .github/scripts/lint-commit-messages.sh 는 ci.yml 주석이 명시하듯 "로컬 훅을
# --no-verify 로 우회했을 때 최종적으로 막아 세우는" 게이트다. 그런데 이 스크립트는
# test-coverage-check.sh 의 스캔 범위(bin/, stow/git/.githooks/) 밖에 있어 오랫동안
# 회귀 테스트가 하나도 없었고, 그 사각지대에서 다음 결함이 실제로 살아 있었다:
#
#   `git rev-list --merges -n1 "$sha"` 는 "$sha 에서 도달 가능한 머지"를 찾는 질의라
#   조상에 머지가 하나라도 있으면 항상 비어있지 않다. 그래서 머지 PR 이 한 번 들어온
#   뒤로는 모든 후속 커밋이 SOURCE="merge" 로 판정돼 commit-msg 훅이 즉시 exit 0 했고,
#   게이트가 통째로 무력화됐다(실측: e914651 머지 이후 24개 커밋 미검증).
#
# 이 스위트는 "머지 커밋만 면제되고 일반 커밋은 반드시 검증된다"는 핵심 계약을 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-lint-commit-messages.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
SUT="$REPO_ROOT/.github/scripts/lint-commit-messages.sh"
ZERO_SHA="0000000000000000000000000000000000000000"

PASS_COUNT=0
FAIL_COUNT=0

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 픽스처 저장소: 이 스크립트는 commit-msg 훅을 "stow/git/.githooks/commit-msg" 라는
# 저장소 루트 기준 상대 경로로 호출하므로, 정본 훅을 같은 상대 위치에 두고 그 안에서 돈다.
FIXTURE="$TMP/repo"
mkdir -p "$FIXTURE/stow/git/.githooks"
cp "$REPO_ROOT/stow/git/.githooks/commit-msg" "$FIXTURE/stow/git/.githooks/commit-msg"
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.email "test@example.com"
git -C "$FIXTURE" config user.name "Test"

# 이 샌드박스는 전역 core.hooksPath 가 실제 훅을 가리켜, 격리 없이 커밋하면 픽스처
# 셋업 중에 SUT 와 무관한 훅이 재귀 발동한다(다른 훅 스위트와 동일 처리).
mk() { git -C "$FIXTURE" -c core.hooksPath=/dev/null commit -q --allow-empty -m "$1"; }

mk "feat: 최초 커밋"
BASE_SHA=$(git -C "$FIXTURE" rev-parse HEAD)
git -C "$FIXTURE" checkout -qb side
mk "feat: 사이드 브랜치 작업"
git -C "$FIXTURE" checkout -q main
mk "feat: 메인 브랜치 작업"
git -C "$FIXTURE" -c core.hooksPath=/dev/null merge -q --no-ff side -m "Merge branch side" >/dev/null 2>&1
MERGE_SHA=$(git -C "$FIXTURE" rev-parse HEAD)

run_sut() {
  local status=0
  (cd "$FIXTURE" && env "$@" bash "$SUT") >"$TMP/out" 2>&1 || status=$?
  echo "$status"
}

echo "=== lint-commit-messages.sh (CI 커밋 컨벤션 최종 게이트) 회귀 테스트 ==="

# 1. 핵심 회귀: 머지 커밋이 히스토리에 있어도, 그 뒤의 일반 커밋은 반드시 검증돼야 한다.
#    예전 --merges -n1 판정에서는 이 케이스가 조용히 통과했다.
mk "이건 컨벤션을 위반한 커밋 메시지"
BAD_SHA=$(git -C "$FIXTURE" rev-parse HEAD)
status=$(run_sut EVENT_NAME=push BEFORE_SHA="$BASE_SHA" AFTER_SHA="$BAD_SHA" PUSHED_SHAS="")
if [ "$status" -eq 1 ] && grep -qF "시맨틱 커밋 컨벤션 위반" "$TMP/out" && grep -qF "$BAD_SHA" "$TMP/out"; then
  report "detect-violation-after-merge (머지 이후 커밋도 검증됨)" 0
else
  report "detect-violation-after-merge (머지 이후 커밋도 검증됨)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 2. 머지 커밋 자신은 Git 이 메시지를 자동 생성하므로 면제되어야 한다(1번 수정의 반대편).
#    머지 커밋 하나만 범위에 넣어 통과하는지 본다.
status=$(run_sut EVENT_NAME=push BEFORE_SHA="$(git -C "$FIXTURE" rev-parse "$MERGE_SHA^")" \
  AFTER_SHA="$MERGE_SHA" PUSHED_SHAS="")
if [ "$status" -eq 0 ]; then
  report "exempt-merge-commit (머지 커밋 자신은 면제)" 0
else
  report "exempt-merge-commit (머지 커밋 자신은 면제)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 3. 정상 커밋만 있으면 통과해야 한다(오탐 방지).
mk "fix(test): 정상적인 시맨틱 커밋"
GOOD_SHA=$(git -C "$FIXTURE" rev-parse HEAD)
status=$(run_sut EVENT_NAME=push BEFORE_SHA="$BAD_SHA" AFTER_SHA="$GOOD_SHA" PUSHED_SHAS="")
if [ "$status" -eq 0 ]; then
  report "pass-valid-commit (정상 커밋은 통과)" 0
else
  report "pass-valid-commit (정상 커밋은 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 4. pull_request 이벤트 경로도 동일하게 위반을 잡아야 한다.
status=$(run_sut EVENT_NAME=pull_request BASE_SHA="$BASE_SHA" HEAD_SHA="$BAD_SHA")
if [ "$status" -eq 1 ] && grep -qF "시맨틱 커밋 컨벤션 위반" "$TMP/out"; then
  report "pull-request-event (PR 이벤트 경로도 검증)" 0
else
  report "pull-request-event (PR 이벤트 경로도 검증)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 5. force-push 로 이전 팁이 사라진 경우, PUSHED_SHAS 폴백으로라도 검증해야 한다
#    (Invalid revision range 로 죽지 않고, 위반도 놓치지 않아야 함).
status=$(run_sut EVENT_NAME=push BEFORE_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
  AFTER_SHA="$GOOD_SHA" PUSHED_SHAS="$BAD_SHA")
if [ "$status" -eq 1 ] && grep -qF "force-push로 히스토리가 재작성됨" "$TMP/out" &&
  grep -qF "시맨틱 커밋 컨벤션 위반" "$TMP/out"; then
  report "force-push-fallback (PUSHED_SHAS 폴백으로 검증)" 0
else
  report "force-push-fallback (PUSHED_SHAS 폴백으로 검증)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 6. 신규 브랜치 push(BEFORE_SHA=0000...)는 팁 커밋만 검증한다.
status=$(run_sut EVENT_NAME=push BEFORE_SHA="$ZERO_SHA" AFTER_SHA="$BAD_SHA" PUSHED_SHAS="")
if [ "$status" -eq 1 ] && grep -qF "시맨틱 커밋 컨벤션 위반" "$TMP/out"; then
  report "new-branch-push (신규 브랜치는 팁 커밋 검증)" 0
else
  report "new-branch-push (신규 브랜치는 팁 커밋 검증)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
