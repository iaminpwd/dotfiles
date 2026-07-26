#!/usr/bin/env bash
# containers 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 010-containers-core.md / 020-image-hardening-standard.md 의 특정
# 조항이나 중단 조건을 재현한다. 목적은 pre-flight-check.sh 의 Dockerfile 검증
# 로직을 손볼 때, 기존 검사가 조용히 죽어서 위반 이미지 정의가 통과되는 상황을
# 막는 것이다.
#
# 검증기가 스테이징된 파일을 대상으로 동작하는 것과 달리 이 러너는 픽스처를
# 직접 넘긴다. 대신 검증기가 쓰는 것과 동일한 명령·옵션을 그대로 사용한다.
#
# 두 검증기의 강제력이 다르므로 그룹을 나눠 표기한다.
#   hadolint         validate_docker 가 실패 시 커밋을 차단한다 (차단 게이트)
#   trivy misconfig  validate_security 가 --exit-code 0 으로 호출하므로 커밋을
#                    막지 않는다. 탐지 여부만 검증한다 (경고 전용)
#
# trivy secret 스캐너용 픽스처는 두지 않는다. 실제로 탐지되는 자격 증명을
# 저장소에 두는 셈이라 시크릿 하드코딩 금지 규칙에 정면으로 어긋나고,
# pre-commit 훅의 trufflehog 가 커밋 자체를 차단한다.
#
# 사용: bash ~/dotfiles/contexts/containers/tests/run.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
CHECKED=()

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
require_tool() {
  command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치 또는 현재 위치에서 실행 불가: $1"
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

# pre-flight-check.sh:419 와 동일하게 'hadolint <file>' 를 호출한다.
# want_rule 이 빈 문자열이면 지적 0건을 기대한다.
run_hadolint() {
  local name=$1 want_rule=${2:-}
  local out status rules
  out=$(hadolint "$FIXTURES/$name" 2>&1) && status=0 || status=$?
  # 지적 0건이면 grep 이 1을 반환해 set -e 에 걸리므로 반드시 흡수해야 한다.
  rules=$(echo "$out" | grep -oE 'DL[0-9]+|SC[0-9]+' | sort -u | tr '\n' ' ' || true)

  if [ -z "$want_rule" ]; then
    if [ "$status" -eq 0 ]; then
      report "$name" 0
    else
      report "$name" 1 "기대: 지적 0건 / 실제: $rules"
    fi
    return
  fi

  if [ "$status" -ne 0 ] && echo "$out" | grep -q "$want_rule"; then
    report "$name" 0
  else
    report "$name" 1 "기대: $want_rule 지적 / 실제 exit=$status, rules=$rules"
  fi
}

# validate_security 의 '--severity HIGH,CRITICAL --scanners misconfig' 와 동일한
# 심각도 필터를 적용한다. want_id 가 빈 문자열이면 HIGH 이상 탐지 0건을 기대한다.
run_trivy_misconfig() {
  local name=$1 want_id=${2:-}
  local ids
  ids=$(trivy config --quiet --severity HIGH,CRITICAL --format json "$FIXTURES/$name" 2>/dev/null |
    python3 -c "
import json,sys
d=json.load(sys.stdin)
print(' '.join(sorted({m['ID'] for r in d.get('Results',[]) for m in r.get('Misconfigurations',[])})))
" 2>/dev/null || echo "__SCAN_ERROR__")

  if [ "$ids" = "__SCAN_ERROR__" ]; then
    report "$name" 1 "trivy config 실행 또는 결과 파싱에 실패했습니다"
    return
  fi

  if [ -z "$want_id" ]; then
    if [ -z "$ids" ]; then
      report "$name" 0
    else
      report "$name" 1 "기대: HIGH 이상 탐지 0건 / 실제: $ids"
    fi
    return
  fi

  if echo " $ids " | grep -q " $want_id "; then
    report "$name" 0
  else
    report "$name" 1 "기대: $want_id 탐지 / 실제: ${ids:-(없음)}"
  fi
}

echo "=== containers 검증 파이프라인 회귀 테스트 ==="

echo "--- hadolint (pre-flight-check.sh / 커밋 차단) ---"
if require_tool hadolint; then
  run_hadolint ok-baseline.Dockerfile ""
  run_hadolint fail-unpinned-base.Dockerfile         DL3007
  run_hadolint fail-unpinned-apt.Dockerfile          DL3018
  run_hadolint fail-shell-form-entrypoint.Dockerfile DL3025
fi

echo "--- trivy misconfig (pre-flight-check.sh / 경고 전용) ---"
if require_tool trivy; then
  run_trivy_misconfig ok-baseline.Dockerfile ""
  run_trivy_misconfig fail-root-user.Dockerfile DS-0002
fi

# 기대 결과가 등록되지 않은 픽스처는 검증되지 않은 채 방치된다.
for path in "$FIXTURES"/*.Dockerfile; do
  name=$(basename "$path")
  found=0
  for c in "${CHECKED[@]}"; do [ "$c" = "$name" ] && found=1 && break; done
  [ "$found" -eq 0 ] && echo "  WARN  $name — 기대 결과가 등록되지 않은 픽스처입니다"
done

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
