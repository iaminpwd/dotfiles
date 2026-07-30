#!/usr/bin/env bash
# compact-runner.sh 회귀 테스트
#
# compact-runner.sh 는 저장소의 모든 검증 게이트를 감싸는 래퍼인데, 정작 검증 게이트
# 계열에서 유일하게 회귀 테스트가 없었고 실제로 두 가지 결함이 있었다(2026-07-28 실측).
#   1. 종료 코드가 아니라 stdout 패턴으로 판정해서, 출력이 전부 무시 패턴에만 걸리는
#      실패 스크립트를 `-> [✓]` 로 표시했다.
#   2. set -e 가 첫 실패에서 루프를 죽여, 남은 검증이 아무 안내 없이 건너뛰어졌다.
# 이 래퍼의 출력을 읽는 주체가 사람과 AI 에이전트이므로 거짓 초록불은 게이트를 통째로
# 무력화한다. 판정 로직을 고칠 때 그 두 결함이 조용히 되살아나지 않는지 확인한다.
#
# pre-flight-check.sh 자체의 검증 로직은 각 클라우드 스킬의 스위트(aws/azure/openstack
# 등)가 픽스처로 덮고 있으므로 여기서 중복 검사하지 않는다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/bin/hooks/compact-runner.sh"
FIXTURES="$TESTS_DIR/fixtures"

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

# check <케이스명> <기대 종료코드> <포함되어야 할 문구|-> <없어야 할 문구|-> <픽스처...>
check() {
  local name=$1 want_code=$2 want_text=$3 deny_text=$4
  shift 4
  local args=() f
  for f in "$@"; do
    args+=("$FIXTURES/$f")
  done

  local out code=0
  out=$(bash "$RUNNER" "${args[@]}" 2>&1) || code=$?

  if [ "$code" -ne "$want_code" ]; then
    report "$name" 1 "기대 exit=$want_code / 실제 exit=$code"
    return
  fi
  if [ "$want_text" != "-" ] && ! grep -qF -- "$want_text" <<<"$out"; then
    report "$name" 1 "출력에 '$want_text' 가 없습니다"
    return
  fi
  if [ "$deny_text" != "-" ] && grep -qF -- "$deny_text" <<<"$out"; then
    report "$name" 1 "출력에 '$deny_text' 가 있으면 안 됩니다: ${out//$'\n'/ }"
    return
  fi
  report "$name" 0
}

echo "=== compact-runner.sh 회귀 테스트 ==="

echo "--- 거짓 초록불 회귀 (2026-07-28 실측 버그) ---"

# 1. 핵심 회귀: 실패인데 출력이 전부 무시 패턴에만 걸리는 경우. 종료 코드 판정으로
#    바뀌기 전에는 여기서 `[✓]` 가 찍혔다.
check "fail-silent (통과 표시 예외)" 1 "exit=1" "[✓]" fail-silent.sh

# 2. 실패 시 원형 로그를 압축하지 않고 보존하는지.
check "fail-verbose (원형 로그 보존)" 1 "FIXTURE_RAW_DETAIL" "-" fail-verbose.sh

echo "--- 무음 스킵 회귀 (2026-07-28 실측 버그) ---"

# 3. 첫 스크립트가 실패해도 남은 스크립트를 계속 실행해야 한다. set -e 로 루프가
#    죽던 시절에는 ok-quiet.sh 가 실행조차 되지 않고 안내도 없었다.
check "실패 후 후속 스크립트 계속 실행" 1 "ok-quiet.sh" "-" fail-silent.sh ok-quiet.sh

# 4. 마지막에 실패 건수 요약을 남기는지.
check "실패 요약 출력" 1 "검증 실패 1/2" "-" fail-silent.sh ok-quiet.sh

echo "--- 통과 경로 (토큰 절약) ---"

# 5. 통과 시 상세 PASS 로그는 접히고 한 줄 요약만 남아야 한다.
check "ok-quiet (상세 로그 압축)" 0 "[✓]" "FIXTURE_QUIET_DETAIL" ok-quiet.sh

# 6. 통과했더라도 경고는 접지 않는다. 접으면 "도구 미설치로 검증을 건너뜀" 신호가
#    사라져 pre-flight-check.sh 의 UNAVAILABLE_TOOLS 경고가 무력화된다.
check "ok-with-warning (경고 보존)" 0 "FIXTURE_SKIPPED_TOOL" "-" ok-with-warning.sh

# 7. 여러 스크립트가 전부 통과하면 exit 0.
check "전건 통과" 0 "[✓]" "❌" ok-quiet.sh ok-with-warning.sh

echo "--- 무검증 통과 통제 ---"

# 8. 실행 대상이 하나도 없으면 exit 0 으로 조용히 넘어가면 안 된다. "전부 통과"와
#    구분되지 않는 무검증 통과가 되기 때문이다. HOME 을 빈 디렉토리로 덮어 정본
#    pre-flight-check.sh 탐색까지 빗나가게 만든 뒤 확인한다.
EMPTY_REPO="$TMP/empty"
mkdir -p "$EMPTY_REPO"
git -C "$EMPTY_REPO" init -q
CODE=0
# compact-runner.sh 는 이제 command -v 로 글로벌 명령어를 탐색한다. HOME 만 바꾸면
# PATH 에서 pre-flight-check.sh 를 찾아내 SCRIPTS 가 채워진다. PATH 를 최소화해
# 글로벌 명령어도 찾히지 않게 만들어야 진짜 0건 시나리오를 재현할 수 있다.
OUT=$( (cd "$EMPTY_REPO" && HOME="$TMP" PATH="/usr/bin:/bin" bash "$RUNNER") 2>&1) || CODE=$?
if [ "$CODE" -eq 1 ] && grep -qF "실행할 검증 스크립트를 찾지 못했습니다" <<<"$OUT"; then
  report "대상 0건이면 실패 처리" 0
else
  report "대상 0건이면 실패 처리" 1 "기대 exit=1 + 안내 문구 / 실제 exit=$CODE"
fi

echo "--- tool-probe.sh 공용 라이브러리 (SSOT) ---"

LIB_CONSUMERS=(
  "$REPO_ROOT/bin/hooks/pre-flight-check.sh"
  "$REPO_ROOT/bin/hooks/plugins/k8s-check.sh"
)

# 9. 라이브러리 계약: source 하면 세 함수가 정의되어야 한다. 소비자의 실행 출력으로
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

# 10. 심볼릭 링크 경로로 호출해도 적재되는지. pre-flight-check.sh 는 저장소 루트 링크로,
#     k8s/scripts/ 는 ~/.claude/skills/k8s/scripts 로 링크되어 배포되므로, BASH_SOURCE 를
#     그대로 쓰면(readlink -f 누락) 링크 위치 기준으로 상대 경로가 빗나간다. 경로가 깨지면
#     source 가 실패하고 set -euo pipefail 이 즉시 죽이므로 완주 여부로 판정한다.
export QUIET=0
#     k8s 스위트는 k8s-check.sh 를 구동하지 않고 로직을 복제 검증하므로, 이 스크립트의
#     라이브러리 적재 경로를 덮는 테스트가 여기 대신는 없다.
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

# 11. SSOT 유지: 소비자가 라이브러리 함수를 다시 정의하면 분리한 의미가 없어진다.
dup=0
for consumer in "${LIB_CONSUMERS[@]}"; do
  grep -qE '^(has_tool|record_unavailable|print_unavailable_tools)\(\)' "$consumer" && dup=1
done
if [ "$dup" -eq 0 ]; then
  report "소비자가 라이브러리 함수를 재정의하지 않음" 0
else
  report "소비자가 라이브러리 함수를 재정의하지 않음" 1 "복제본이 되살아났습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
