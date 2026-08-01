#!/usr/bin/env bash
# observability 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 020-metrics-alerting-standard.md 4절의 중단 조건을 재현한다. 목적은
# validate-alert-rules.sh(bin/hooks/plugins/observability-check.sh 가 커밋 시점에
# 호출하는 검증기 본체)를 손볼 때, 기존 검사가 조용히 죽어서 위반 알람 규칙이
# 통과되는 상황을 제어하는 것이다.
#
# 검증기가 스테이징된 파일을 대상으로 동작하는 것과 달리 이 러너는 픽스처를
# validate-alert-rules.sh 에 직접 넘긴다. observability-check.sh 와 동일한 스크립트를
# 그대로 호출하므로, 파이프라인이 실제로 잡는 것만 잡는다고 주장하도록 맞췄다.
#
# 사용: bash ~/dotfiles/contexts/observability/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
VALIDATOR="$TESTS_DIR/../scripts/validate-alert-rules.sh"

PASS_COUNT=0
FAIL_COUNT=0

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치: $1 — 'mise install $1' 후 다시 실행하십시오"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

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

# want_fail=1 이면 검증기가 반드시 비정상 종료해야 하고, want_pattern 이 주어지면
# 출력에 해당 문구가 실제로 등장했는지까지 확인한다. 종료 코드만 보면 다른 이유로
# 실패해도 통과로 오판할 수 있다.
run_validator() {
  local name=$1 want_fail=$2 want_pattern=${3:-}
  local out status
  out=$(bash "$VALIDATOR" "$FIXTURES/$name" 2>&1) && status=0 || status=$?

  if [ -n "$want_pattern" ] && ! grep -qF "$want_pattern" <<<"$out"; then
    report "$name" 1 "기대 문구 '$want_pattern' 가 출력에 없습니다 (exit=$status): $(echo "$out" | tail -1)"
    return
  fi

  if [ "$want_fail" -eq 1 ] && [ "$status" -ne 0 ]; then
    report "$name" 0
  elif [ "$want_fail" -eq 0 ] && [ "$status" -eq 0 ]; then
    report "$name" 0
  else
    report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo '위반 검출' || echo '통과') / 실제 exit=$status: $(echo "$out" | tail -1)"
  fi
}

echo "=== observability 검증 파이프라인 회귀 테스트 ==="

echo "--- validate-alert-rules.sh (observability-check.sh) ---"
if require_tool yq; then
  run_validator ok-baseline.yaml 0
  run_validator fail-missing-runbook.yaml 1 "runbook_url 누락"
  run_validator fail-high-cardinality-label.yaml 1 "고카디널리티 레이블 감지"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
