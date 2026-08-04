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
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
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

echo "--- observability-check.sh (bin/hooks/plugins, 커밋 시점 배선) ---"
# validate-alert-rules.sh를 직접 호출하는 위 섹션은 "판정 로직이 맞는가"만 본다.
# observability-check.sh 자신의 오케스트레이션(스테이징된 yaml 중 kind: PrometheusRule만
# 골라 트리거하는지, 무관한 kind:는 건드리지 않는지)은 이름이 주석에만 언급될 뿐 실제로
# bash 호출되는 테스트가 없어 test-coverage-check.sh의 경고 레이어에 걸렸다
# (2026-08-05). aiops-check.sh와 동일한 패턴으로 격리 저장소에서 실제 호출까지 검증한다.
if require_tool yq; then
  OBS_PLUGIN="$REPO_ROOT/bin/hooks/plugins/observability-check.sh"
  if [ -x "$OBS_PLUGIN" ]; then
    PLUGIN_TMP=$(mktemp -d)

    run_plugin() {
      local repo=$1 status=0
      (cd "$repo" && QUIET=0 bash "$OBS_PLUGIN") >"$PLUGIN_TMP/out" 2>&1 || status=$?
      echo "$status"
    }

    # Case 1: kind: PrometheusRule + runbook_url 누락 -> 커밋 차단.
    OR1="$PLUGIN_TMP/repo1"
    mkdir -p "$OR1"
    git -C "$OR1" init -q
    git -C "$OR1" config user.email test@example.com
    git -C "$OR1" config user.name Test
    cp "$FIXTURES/fail-missing-runbook.yaml" "$OR1/rule.yaml"
    git -C "$OR1" add rule.yaml
    status=$(run_plugin "$OR1")
    if [ "$status" -eq 1 ] && grep -qF "알람 정책" "$PLUGIN_TMP/out"; then
      report "trigger-and-block (kind: PrometheusRule + runbook_url 누락 -> 차단)" 0
    else
      report "trigger-and-block (kind: PrometheusRule + runbook_url 누락 -> 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # Case 2: kind: PrometheusRule + 정책 위반 없음 -> 통과.
    OR2="$PLUGIN_TMP/repo2"
    mkdir -p "$OR2"
    git -C "$OR2" init -q
    git -C "$OR2" config user.email test@example.com
    git -C "$OR2" config user.name Test
    cp "$FIXTURES/ok-baseline.yaml" "$OR2/rule.yaml"
    git -C "$OR2" add rule.yaml
    status=$(run_plugin "$OR2")
    if [ "$status" -eq 0 ]; then
      report "trigger-and-pass (kind: PrometheusRule + 위반 없음 -> 통과)" 0
    else
      report "trigger-and-pass (kind: PrometheusRule + 위반 없음 -> 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # Case 3: 무관한 kind:(PrometheusRule 아님)는 정책 위반스러운 내용이 있어도 트리거되면 안 된다.
    OR3="$PLUGIN_TMP/repo3"
    mkdir -p "$OR3"
    git -C "$OR3" init -q
    git -C "$OR3" config user.email test@example.com
    git -C "$OR3" config user.name Test
    cat >"$OR3/deployment.yaml" <<'EOF'
kind: Deployment
metadata:
  name: unrelated
spec:
  labels:
    user_id: something
EOF
    git -C "$OR3" add deployment.yaml
    status=$(run_plugin "$OR3")
    if [ "$status" -eq 0 ]; then
      report "no-trigger-on-unrelated-kind (PrometheusRule 아니면 무동작)" 0
    else
      report "no-trigger-on-unrelated-kind (PrometheusRule 아니면 무동작)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    rm -rf "$PLUGIN_TMP"
  else
    report "observability-check.sh 플러그인 배선 확인" 1 "bin/hooks/plugins/observability-check.sh 를 찾을 수 없거나 실행 권한이 없습니다"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
