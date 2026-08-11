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

# yq 부재와 "PrometheusRule 구조가 아님"은 원인도 조치도 전혀 다른데, 예전엔 둘 다
# 후자로 보고해 yq만 없는 상황에서 파일을 붙잡고 고치게 만들었다. 먼저 구분해 둔다.
if ! command -v yq >/dev/null 2>&1; then
  echo "[FAIL] yq 를 찾을 수 없어 알람 정책을 검증할 수 없습니다 ('mise install -y' 후 다시 시도하십시오)" >&2
  exit 1
fi

# 규칙마다 yq 프로세스를 5회(alert/severity/runbook + 고카디널리티 레이블 2종) 띄우던
# 것을 단일 호출로 합친다. 규칙 50건 파일 실측 기준 251회 스폰 -> 1회, 13.1초 -> 0.1초.
# observability-check.sh 가 커밋 시점마다 파일별로 호출하므로 규칙 수에 비례한 지연이
# 그대로 커밋 대기 시간이 됐다.
#
# DENYLISTED_LABEL_KEYS 를 데이터로 유지하기 위해(위 주석의 "룰북에 명시된 값만" 원칙)
# 레이블 추출식은 배열에서 동적으로 조립한다. 하드코딩하면 목록을 늘릴 때 두 곳을
# 고쳐야 하고 한쪽이 조용히 낡는다.
LABEL_EXPRS=""
for key in "${DENYLISTED_LABEL_KEYS[@]}"; do
  LABEL_EXPRS="$LABEL_EXPRS, (.labels.${key} // \"\")"
done

# 필드를 한 줄에 하나씩 뽑되, 반드시 "규칙별 배열([...])을 만든 뒤 .[] 로 펼치는" 형태여야
# 한다. 이 표현식 형태는 두 가지 함정을 동시에 피한다:
#
#  1. 탭 구분(@tsv) + `IFS=$'\t' read` 조합은 쓸 수 없다. 탭은 IFS 공백문자라 bash 가
#     연속 탭을 구분자 하나로 합쳐 빈 필드를 삼킨다. runbook 미설정·레이블 미사용은
#     정상 케이스라 그 자리에서 필드가 통째로 밀려 판정이 조용히 어긋난다.
#  2. 배열 없이 `.[] | (a), (b), (c)` 로 쓰면 안 된다. yq 에서 `,` 는 `|` 보다 결합력이
#     약해 두 번째 이후 표현식이 각 규칙이 아니라 스트림 전체에 적용된다. 그러면 출력이
#     행 단위가 아니라 열 단위(alert 전체 -> severity 전체 -> ...)로 나와, 규칙이 2건
#     이상일 때 필드가 전부 어긋난다. 규칙 1건짜리 파일에서는 두 순서가 우연히 일치해
#     증상이 안 드러나므로 반드시 다중 규칙 픽스처로 검증할 것.
RULE_FIELDS=()
mapfile -t RULE_FIELDS < <(
  yq eval -r "[.spec.groups[].rules[]] | .[] | [(.alert // \"(이름 없음)\"), (.labels.severity // \"\"), (.annotations.runbook_url // \"\")${LABEL_EXPRS}] | .[]" "$FILE" 2>/dev/null
) || {
  echo "[FAIL] $FILE — .spec.groups[].rules[] 파싱에 실패했습니다 (PrometheusRule 구조가 아님)" >&2
  exit 1
}

# 규칙 1건당 고정 필드 수: alert/severity/runbook_url + 검사 대상 레이블 개수
FIELDS_PER_RULE=$((3 + ${#DENYLISTED_LABEL_KEYS[@]}))
VIOLATIONS=0

for ((base = 0; base + FIELDS_PER_RULE <= ${#RULE_FIELDS[@]}; base += FIELDS_PER_RULE)); do
  ALERT_NAME="${RULE_FIELDS[base]}"
  SEVERITY="${RULE_FIELDS[base + 1]}"
  RUNBOOK="${RULE_FIELDS[base + 2]}"

  if [ "$SEVERITY" = "critical" ] && [ -z "$RUNBOOK" ]; then
    echo "[FAIL] Critical 알람에 runbook_url 누락: $ALERT_NAME"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  for ((k = 0; k < ${#DENYLISTED_LABEL_KEYS[@]}; k++)); do
    if [ -n "${RULE_FIELDS[base + 3 + k]}" ]; then
      echo "[FAIL] 고카디널리티 레이블 감지: $ALERT_NAME label=${DENYLISTED_LABEL_KEYS[k]}"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "[FAIL] $FILE — 정책 위반 $VIOLATIONS 건" >&2
  exit 1
fi

echo "[OK] $FILE — 정책 위반 없음"
