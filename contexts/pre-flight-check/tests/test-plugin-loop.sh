#!/usr/bin/env bash
# test-plugin-loop.sh
#
# run_delegated_skill_checks() 가 첫 플러그인 실패에서 즉시 중단하면 뒤 플러그인은
# 실행조차 안 됐다. PrometheusRule YAML은 k8s-check.sh(PromQL 문법)와
# observability-check.sh(알람 정책) 양쪽의 대상이라, 파일 하나가 두 플러그인을
# 동시에 위반할 수 있다. 글롭이 알파벳 순으로 k8s-check.sh 를 먼저 도니, 예전
# fail-fast 구조에서는 observability-check.sh 의 위반이 재커밋 전까지 드러나지
# 않았다(2026-08-01 실측). 두 플러그인이 실제로 둘 다 끝까지 실행되고 둘 다
# 보고하는지 고정한다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-plugin-loop.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

echo "--- 플러그인 루프 exhaustive 판정 (2026-08-01 실측 버그) ---"

if command -v yq >/dev/null 2>&1 && command -v promtool >/dev/null 2>&1; then
  PLUGIN_REPO="$TMP/plugin-loop"
  mkdir -p "$PLUGIN_REPO"
  git -C "$PLUGIN_REPO" init -q
  cat >"$PLUGIN_REPO/both-plugins-fail.yaml" <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: fail-both-plugins
  namespace: sample
spec:
  groups:
    - name: sample.rules
      rules:
        - alert: BrokenAndUnrunbooked
          expr: rate(http_requests_total[5m] > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: PromQL 문법 오류 + runbook_url 누락 동시 재현
EOF
  git -C "$PLUGIN_REPO" add both-plugins-fail.yaml
  CODE=0
  OUT=$( (cd "$PLUGIN_REPO" && QUIET=0 bash "$REPO_ROOT/bin/hooks/pre-flight-check.sh") 2>&1) || CODE=$?
  if [ "$CODE" -eq 1 ] && grep -qF "PromQL Alerting Rule 문법 검증에 실패" <<<"$OUT" && grep -qF "알람 정책" <<<"$OUT"; then
    report "플러그인 루프가 두 위반 모두 보고" 0
  else
    report "플러그인 루프가 두 위반 모두 보고" 1 "exit=$CODE / k8s 문구 감지=$(grep -qF 'PromQL Alerting Rule 문법 검증에 실패' <<<"$OUT" && echo yes || echo no), observability 문구 감지=$(grep -qF '알람 정책' <<<"$OUT" && echo yes || echo no)"
  fi
else
  report "플러그인 루프가 두 위반 모두 보고" 1 "도구 미설치: yq 또는 promtool — 'mise install' 후 다시 실행하십시오"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
