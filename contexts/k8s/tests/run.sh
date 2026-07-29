#!/usr/bin/env bash
# k8s 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 010-k8s-core.md 의 특정 조항이나 중단 조건을 재현한다. 목적은
# pre-flight-check.sh / k8s-check.sh 가 호출하는 검증기를 손볼 때, 기존 검사가
# 조용히 죽어서 위반 매니페스트가 통과되는 상황을 제어하는 것이다.
#
# 검증기가 스테이징된 파일을 대상으로 동작하는 것과 달리 이 러너는 픽스처를
# 직접 넘긴다. 대신 검증기가 쓰는 것과 동일한 명령·옵션을 그대로 사용해,
# 파이프라인이 실제로 잡는 것만 잡는다고 주장하도록 맞췄다.
#
# 사용: bash ~/dotfiles/contexts/k8s/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
CHECKED=()

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
  CHECKED+=("$name")
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# pre-flight-check.sh 의 validate_k8s_manifests 와 동일하게 'kube-linter lint <file>' 를 호출한다.
# want_check 가 빈 문자열이면 지적 0건을 기대한다.
run_kube_linter() {
  local name=$1 want_check=${2:-}
  local out status
  out=$(kube-linter lint "$FIXTURES/$name" 2>&1) && status=0 || status=$?

  if [ -z "$want_check" ]; then
    if [ "$status" -eq 0 ]; then
      report "$name" 0
    else
      report "$name" 1 "기대: 지적 0건 / 실제: $(grep -oE '\(check: [a-z-]+' <<<"$out" | sed 's/(check: //' | sort -u | tr '\n' ' ')"
    fi
    return
  fi

  if [ "$status" -ne 0 ] && grep -q "(check: $want_check" <<<"$out"; then
    report "$name" 0
  else
    report "$name" 1 "기대: '$want_check' 지적 / 실제 exit=$status, checks=$(grep -oE '\(check: [a-z-]+' <<<"$out" | sed 's/(check: //' | sort -u | tr '\n' ' ')"
  fi
}

# k8s-check.sh 의 check_prometheus_rules 와 동일하게 yq 로 .spec 을 벗겨 promtool 에 넘긴다.
run_promtool() {
  local name=$1 want_fail=$2
  local tmp out status
  tmp=$(mktemp)
  yq eval '.spec' "$FIXTURES/$name" >"$tmp"
  out=$(promtool check rules "$tmp" 2>&1) && status=0 || status=$?
  rm -f "$tmp"

  if [ "$want_fail" -eq 1 ] && [ "$status" -ne 0 ]; then
    report "$name" 0
  elif [ "$want_fail" -eq 0 ] && [ "$status" -eq 0 ]; then
    report "$name" 0
  else
    report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo '문법 오류 검출' || echo '통과') / 실제 exit=$status: $(echo "$out" | tail -1)"
  fi
}

# k8s-check.sh 의 check_deprecated_apis 와 동일하게 'pluto detect-files -d <dir>' 를 호출한다.
# pluto 는 디렉토리 단위로 스캔하므로 픽스처마다 격리된 임시 디렉토리를 쓴다.
run_pluto() {
  local name=$1 want_fail=$2
  local dir out status
  dir=$(mktemp -d)
  cp "$FIXTURES/$name" "$dir/"
  out=$(pluto detect-files -d "$dir" 2>&1) && status=0 || status=$?
  rm -rf "$dir"

  if [ "$want_fail" -eq 1 ] && [ "$status" -ne 0 ]; then
    report "$name" 0
  elif [ "$want_fail" -eq 0 ] && [ "$status" -eq 0 ]; then
    report "$name" 0
  else
    report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo 'deprecated API 검출' || echo '통과') / 실제 exit=$status: $(echo "$out" | tail -1)"
  fi
}

echo "=== k8s 검증 파이프라인 회귀 테스트 ==="

echo "--- kube-linter (pre-flight-check.sh) ---"
if require_tool kube-linter; then
  run_kube_linter ok-baseline.yaml ""
  run_kube_linter fail-privileged.yaml privileged-container
  run_kube_linter fail-host-network.yaml host-network
  run_kube_linter fail-run-as-root.yaml run-as-non-root
  run_kube_linter fail-unset-resources.yaml unset-memory-requirements
fi

echo "--- promtool (k8s-check.sh) ---"
if require_tool promtool && require_tool yq; then
  run_promtool ok-prometheus-rule.yaml 0
  run_promtool fail-promql-syntax.yaml 1
fi

echo "--- pluto (k8s-check.sh) ---"
if require_tool pluto; then
  run_pluto ok-baseline.yaml 0
  run_pluto fail-deprecated-api.yaml 1
fi

# 기대 결과가 등록되지 않은 픽스처는 검증되지 않은 채 방치된다.
for path in "$FIXTURES"/*.yaml; do
  name=$(basename "$path")
  found=0
  for c in "${CHECKED[@]}"; do [ "$c" = "$name" ] && found=1 && break; done
  [ "$found" -eq 0 ] && echo "  WARN  $name — 기대 결과가 등록되지 않은 픽스처입니다"
done

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
