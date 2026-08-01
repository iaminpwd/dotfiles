#!/usr/bin/env bash
# validate-alert-rules.sh - PrometheusRule 정책 검증기 (020-metrics-alerting-standard.md §4)
#
# promtool 은 PromQL 문법만 검증하고(k8s-check.sh 의 check_prometheus_rules 가 담당),
# 020-metrics-alerting-standard.md 가 요구하는 아래 두 중단 조건은 문법 검사로는
# 잡히지 않는 의미론적 정책이라 이 스크립트가 별도로 담당한다:
#   1. Critical 등급 알람은 annotations.runbook_url 이 비어있으면 안 됨.
#   2. 레이블에 user_id/client_ip 등 통제되지 않은 고유값 카디널리티를 바인딩하면 안 됨.
#
# bin/hooks/plugins/observability-check.sh(실 커밋 파이프라인)와
# contexts/observability/tests/run.sh(회귀 테스트) 양쪽이 이 스크립트를 그대로 호출한다.
# 판정 로직을 두 곳에 복제하면 한쪽만 고치고 다른 쪽을 놓치는 사고가 나기 쉽기 때문이다
# (aws/azure/openstack 이 tf-fixture-lib.sh 를 공유하는 것과 동일한 이유).
#
# 사용: validate-alert-rules.sh <PrometheusRule YAML 경로>
# 종료 코드: 0=정책 위반 없음, 1=위반 감지 또는 파싱 실패

set -euo pipefail

# 고카디널리티로 통제 불가능한 레이블 키 목록. 020-metrics-alerting-standard.md 4절이
# 예시로 든 두 값만 다룬다("user_id/client_ip 등") — 문서에 명시되지 않은 값까지
# 추측해서 넣으면 이 스크립트가 룰북보다 더 엄격한 별도 정책을 임의로 강제하게 된다.
DENYLISTED_LABEL_KEYS=(user_id client_ip)

FILE=${1:?사용법: validate-alert-rules.sh <PrometheusRule YAML 경로>}

if [ ! -f "$FILE" ]; then
  echo "[FAIL] 파일을 찾을 수 없습니다: $FILE" >&2
  exit 1
fi

RULE_COUNT=$(yq eval '[.spec.groups[].rules[]] | length' "$FILE" 2>/dev/null) || {
  echo "[FAIL] $FILE — .spec.groups[].rules[] 파싱에 실패했습니다 (PrometheusRule 구조가 아님)" >&2
  exit 1
}

VIOLATIONS=0

for ((i = 0; i < RULE_COUNT; i++)); do
  ALERT_NAME=$(yq eval "[.spec.groups[].rules[]][$i].alert // \"(이름 없음)\"" "$FILE")
  SEVERITY=$(yq eval "[.spec.groups[].rules[]][$i].labels.severity // \"\"" "$FILE")
  RUNBOOK=$(yq eval "[.spec.groups[].rules[]][$i].annotations.runbook_url // \"\"" "$FILE")

  if [ "$SEVERITY" = "critical" ] && [ -z "$RUNBOOK" ]; then
    echo "[FAIL] Critical 알람에 runbook_url 누락: $ALERT_NAME"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  for key in "${DENYLISTED_LABEL_KEYS[@]}"; do
    label_val=$(yq eval "[.spec.groups[].rules[]][$i].labels.${key} // \"\"" "$FILE")
    if [ -n "$label_val" ]; then
      echo "[FAIL] 고카디널리티 레이블 감지: $ALERT_NAME label=$key"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "[FAIL] $FILE — 정책 위반 $VIOLATIONS 건" >&2
  exit 1
fi

echo "[OK] $FILE — 정책 위반 없음"
