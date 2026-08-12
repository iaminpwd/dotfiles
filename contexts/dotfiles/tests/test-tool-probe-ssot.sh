#!/usr/bin/env bash
# test-tool-probe-ssot.sh
#
# bin/lib/tool-probe.sh 는 has_tool/record_unavailable/print_unavailable_tools
# 세 함수를 여러 소비자(pre-flight-check.sh, k8s-check.sh, container-hardening-gate.sh)가
# 공유하는 SSOT다. 소비자가 이 계약을 깨거나 함수를 재정의로 되살리면 도구 미설치 시
# 우아한 강등(WARNING+skip)이 조용히 하드 블록으로 바뀔 수 있다.
#
# container-hardening-gate.sh 는 인자(Dockerfile/이미지 경로)가 없으면 즉시 exit 1 하는
# 계약이라 아래 2번(인자 없이 심볼릭 링크 호출) 스모크 테스트에는 넣지 않는다. 그 스크립트의
# 실제 동작(DS-0002 판정)은 contexts/containers/tests/run.sh 가 fixture로 검증한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-tool-probe-ssot.sh

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

echo "--- tool-probe.sh 공용 라이브러리 (SSOT) ---"

LIB_CONSUMERS=(
  "$REPO_ROOT/bin/hooks/pre-flight-check.sh"
  "$REPO_ROOT/bin/hooks/plugins/k8s-check.sh"
)

# 1. 라이브러리 계약: source 하면 세 함수가 정의되어야 한다. 소비자의 실행 출력으로
#    적재 여부를 추정하면 스테이징 상태에 따라 결과가 흔들리므로(검증 대상 파일 목록에
#    tool-probe.sh 자신이 들어오면 그 경로가 정상 출력에 섞인다) 계약을 직접 확인한다.
LIB="$REPO_ROOT/bin/lib/tool-probe.sh"
code=0
bash -c 'set -euo pipefail
export QUIET=0
  source "$1"
  for fn in has_tool record_unavailable print_unavailable_tools; do
    declare -F "$fn" >/dev/null || exit 1
  done' _ "$LIB" || code=$?
if [ "$code" -eq 0 ]; then
  report "tool-probe.sh 가 세 함수를 제공" 0
else
  report "tool-probe.sh 가 세 함수를 제공" 1 "exit=$code"
fi

# 2. 심볼릭 링크 경로로 호출해도 적재되는지. pre-flight-check.sh 는 저장소 루트 링크로,
#    k8s/scripts/ 는 ~/.claude/skills/k8s/scripts 로 링크되어 배포되므로, BASH_SOURCE 를
#    그대로 쓰면(readlink -f 누락) 링크 위치 기준으로 상대 경로가 빗나간다. 경로가 깨지면
#    source 가 실패하고 set -euo pipefail 이 즉시 죽이므로 완주 여부로 판정한다.
export QUIET=0
#    k8s 스위트는 k8s-check.sh 를 구동하지 않고 로직을 복제 검증하므로, 이 스크립트의
#    라이브러리 적재 경로를 덮는 테스트가 여기 대신는 없다.
for consumer in "${LIB_CONSUMERS[@]}"; do
  name=$(basename "$consumer")
  ln -sfn "$(readlink -f "$consumer")" "$TMP/link-$name"
  code=0
  out=$( (cd "$TMP" && bash "$TMP/link-$name") 2>&1) || code=$?
  if [ "$code" -eq 0 ]; then
    report "$name 심볼릭 링크 호출" 0
  else
    report "$name 심볼릭 링크 호출" 1 "exit=$code / $(tail -1 <<<"$out")"
  fi
done

# 3. SSOT 유지: 소비자가 라이브러리 함수를 다시 정의하면 분리한 의미가 없어진다.
#    (인자 계약 때문에 2번 스모크 테스트에서 빠진 container-hardening-gate.sh도 정적 grep인
#    이 검사에는 안전하게 포함된다.)
DUP_CHECK_CONSUMERS=(
  "${LIB_CONSUMERS[@]}"
  "$REPO_ROOT/bin/linters/container-hardening-gate.sh"
)
dup=0
for consumer in "${DUP_CHECK_CONSUMERS[@]}"; do
  grep -qE '^(has_tool|record_unavailable|print_unavailable_tools)\(\)' "$consumer" && dup=1
done
if [ "$dup" -eq 0 ]; then
  report "소비자가 라이브러리 함수를 재정의하지 않음" 0
else
  report "소비자가 라이브러리 함수를 재정의하지 않음" 1 "복제본이 되살아났습니다"
fi

# 4. print_unavailable_tools()의 모든 출력 줄이 [WARNING]로 시작해야 한다. run-suite.sh는
#    통과한 스크립트 출력에서 [WARNING]/⚠로 시작하는 줄만 압축 없이 남기므로(bin/hooks/
#    run-suite.sh 참조), "===" 접두어만 쓰면 도구 미설치로 검증이 건너뛰어져도 압축 경로
#    에서는 통째로 안 보이는 거짓 초록불이 된다(과거 실제 재현된 버그: 세 줄 다 미보존).
code=0
OUT=$(bash -c '
  set -euo pipefail
  export QUIET=0
  source "$1"
  UNAVAILABLE_TOOLS=("terraform")
  print_unavailable_tools
' _ "$LIB" 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ -n "$OUT" ] && ! grep -qvE '^\[WARNING\]' <<<"$OUT"; then
  report "print_unavailable_tools 모든 줄이 [WARNING]로 시작" 0
else
  report "print_unavailable_tools 모든 줄이 [WARNING]로 시작" 1 "out=$OUT"
fi

# 5. 플러그인(bin/hooks/plugins/*.sh)은 tool-probe.sh 를 "조건부"로 source 한다(파일이
#    없으면 건너뜀). 그런데 print_unavailable_tools 를 무가드로 호출하면, 라이브러리를
#    못 찾은 환경에서 set -e 가 그 자리에서 스크립트를 죽여 "검증 실패"로 오보고된다.
#    세 플러그인 중 aiops 만 declare -F 로 감싸고 나머지 둘은 무방비였다 — 같은 패턴을
#    서로 다르게 방어하던 상태라, 셋 다 가드를 갖추도록 고정한다.
unguarded=()
for plugin in "$REPO_ROOT"/bin/hooks/plugins/*.sh; do
  [ -f "$plugin" ] || continue
  grep -qF "print_unavailable_tools" "$plugin" || continue
  grep -qF "declare -F print_unavailable_tools" "$plugin" || unguarded+=("$(basename "$plugin")")
done
if [ "${#unguarded[@]}" -eq 0 ]; then
  report "플러그인이 print_unavailable_tools 를 가드 후 호출" 0
else
  report "플러그인이 print_unavailable_tools 를 가드 후 호출" 1 "무가드: ${unguarded[*]}"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
