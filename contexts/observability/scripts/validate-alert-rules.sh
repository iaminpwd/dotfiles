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
#  3. 값 자체에 개행이 들어갈 수 있다. 줄 하나 = 필드 하나라는 전제는 "필드 값에 개행이
#     없다"에 기대는데, 긴 runbook_url 을 접힌 스칼라(`runbook_url: >`)로 쓰는 것은
#     흔한 YAML 관례이고 그때 값 끝에 개행이 붙는다. 그러면 그 규칙부터 필드가 한 칸씩
#     밀려 이후 전부 어긋난다(실측: 접힌 스칼라를 쓴 규칙 뒤에 runbook_url 없는 critical
#     알람과 client_ip 레이블을 둔 파일이 위반 2건을 모두 놓치고 [OK] exit 0 으로 통과).
#     그래서 각 필드를 `tostring | sub("\n"; " ")` 로 한 줄로 정규화한 뒤 내보낸다.
#     sub 는 전역 치환이고, 판정이 보는 것은 "비었는가"와 알람 이름 표시뿐이라 개행을
#     공백으로 바꿔도 결과가 달라지지 않는다. tostring 은 `severity: 5` 처럼 값이 문자열이
#     아닐 때 sub 가 죽는 것을 막는다.
# [주의] 아래를 `mapfile -t ARR < <(yq ...) || { 실패처리 }` 로 쓰면 안 된다. mapfile 은
# 프로세스 치환의 종료 코드를 전파하지 않고, 입력이 비면 빈 배열을 만든 뒤 그냥 0을
# 반환한다(실측: `mapfile -t A < <(false); echo $?` -> 0). 그래서 그 형태에서는 실패
# 처리 분기가 영영 도달하지 못하고, 파싱이 깨진 파일이 "규칙 0건 = 위반 0건"으로 흘러
# [OK] 로 통과했다(실측: spec.groups 를 groupz 로 오타 낸 PrometheusRule 에서 runbook_url
# 없는 critical 알람이 exit 0 으로 통과). 종료 코드를 독립적으로 받는 형태로 바꾼다.

# 1) 구조 판정. yq 는 실패 유형마다 신호가 달라 rc 만으로는 부족하다:
#      정상            -> rc=0, .spec.groups 가 !!seq
#      키 오타(groupz) -> rc=0, .spec.groups 가 !!null   <- rc 만 보면 못 잡는다
#      YAML 깨짐       -> rc=1
#      groups: []      -> rc=0, !!seq (규칙 0건은 정상이므로 통과시켜야 한다)
#    따라서 "시퀀스인가"까지 확인해야 네 경우가 모두 구분된다.
#    (명령 치환은 mapfile 과 달리 종료 코드를 그대로 전파하므로 || 처리가 유효하다.)
GROUPS_TYPE=$(yq eval -r '.spec.groups | type' "$FILE" 2>/dev/null) || {
  echo "[FAIL] $FILE — YAML 파싱에 실패했습니다 (문법 오류)" >&2
  exit 1
}
if [ "$GROUPS_TYPE" != "!!seq" ]; then
  echo "[FAIL] $FILE — .spec.groups 가 시퀀스가 아닙니다 (현재: $GROUPS_TYPE)." >&2
  echo "        PrometheusRule 구조가 맞는지, spec.groups 키에 오타가 없는지 확인하십시오." >&2
  exit 1
fi

# 2) 필드 추출. 규칙 수에 비례하던 yq 스폰을 없앤다는 위 최적화 취지는 그대로다
#    (규칙 50건 기준 251회 -> 파일당 고정 2회).
RULE_FIELDS=()
YQ_OUT=$(mktemp)
trap 'rm -f "$YQ_OUT"' EXIT
if ! yq eval -r "[.spec.groups[].rules[]] | .[] | [(.alert // \"(이름 없음)\"), (.labels.severity // \"\"), (.annotations.runbook_url // \"\")${LABEL_EXPRS}] | .[] | tostring | sub(\"\n\"; \" \")" "$FILE" >"$YQ_OUT" 2>/dev/null; then
  echo "[FAIL] $FILE — .spec.groups[].rules[] 추출에 실패했습니다" >&2
  exit 1
fi
mapfile -t RULE_FIELDS <"$YQ_OUT"

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
