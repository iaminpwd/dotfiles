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
# (여러 스킬의 테스트가 .shared/test-lib/parallel-pair.sh 를 공유하는 것과 동일한 이유).
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

# yq 부재와 "PrometheusRule 구조가 아님"은 원인도 조치도 전혀 다른데, 예전엔 둘 다
# 후자로 보고해 yq만 없는 상황에서 파일을 붙잡고 고치게 만들었다. 먼저 구분해 둔다.
if ! command -v yq >/dev/null 2>&1; then
  echo "[FAIL] yq 를 찾을 수 없어 알람 정책을 검증할 수 없습니다 ('mise install -y' 후 다시 시도하십시오)" >&2
  exit 1
fi

# YAML은 한 번만 JSON 문서 스트림으로 변환한다. jq는 문서 선택·구조 판정·규칙
# 추출을 한 번에 처리하므로 문서 수가 늘어도 전체 파일을 반복 파싱하지 않는다.
if ! command -v jq >/dev/null 2>&1; then
  echo "[FAIL] jq 를 찾을 수 없어 알람 정책을 검증할 수 없습니다" >&2
  exit 1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! yq eval -o=json -I=0 '.' "$FILE" >"$TMP/docs.json" 2>/dev/null; then
  echo "[FAIL] $FILE — YAML 파싱에 실패했습니다 (문법 오류)" >&2
  exit 1
fi

# kind가 있는 PrometheusRule을 우선 선택하고, 없으면 종전처럼 전체 문서를 검사한다.
# 빈 groups는 정상이며, 줄바꿈이 있는 필드도 규칙 사이의 경계를 바꾸지 않는다.
# shellcheck disable=SC2016
if ! jq -rs --arg file "$FILE" --arg keys "${DENYLISTED_LABEL_KEYS[*]}" '
  def text: tostring | gsub("\n"; " ");
  to_entries as $docs
  | [$docs[] | select(.value.kind == "PrometheusRule")] as $selected
  | (if $selected | length > 0 then $selected else $docs end)[]
  | .key as $index | .value
  | if (.spec.groups | type) != "array" then
      "[FAIL] \($file) (문서 \($index)) — .spec.groups 가 시퀀스가 아닙니다."
    else
      .spec.groups[].rules[]? as $rule
      | ($rule.alert // "(이름 없음)" | text) as $name
      | (if ($rule.labels.severity // "" | text) == "critical" and
             ($rule.annotations.runbook_url // "" | text) == "" then
           "[FAIL] Critical 알람에 runbook_url 누락: \($name)"
         else empty end),
        ($keys | split(" ")[] as $key
         | select(($rule.labels[$key] // "" | text) != "")
         | "[FAIL] 고카디널리티 레이블 감지: \($name) label=\($key)")
    end
' "$TMP/docs.json" >"$TMP/violations" 2>/dev/null; then
  echo "[FAIL] $FILE — 규칙 구조를 읽지 못했습니다" >&2
  exit 1
fi

if [ -s "$TMP/violations" ]; then
  cat "$TMP/violations"
  echo "[FAIL] $FILE — 정책 위반 감지"
  exit 1
fi
echo "[OK] $FILE — 알람 정책 검증 통과"
