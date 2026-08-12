#!/usr/bin/env bash
# test-run-suite.sh
#
# run-suite.sh(구 compact-runner.sh)는 저장소의 모든 검증 게이트를 감싸는 래퍼인데, 정작 검증 게이트
# 계열에서 유일하게 회귀 테스트가 없으면 아래 두 가지 결함이 조용히 되살아날 수 있다.
#   1. 종료 코드가 아니라 stdout 패턴으로 판정해서, 출력이 전부 무시 패턴에만 걸리는
#      실패 스크립트를 `-> [✓]` 로 표시했다.
#   2. set -e 가 첫 실패에서 루프를 죽여, 남은 검증이 아무 안내 없이 건너뛰어졌다.
# 이 래퍼의 출력을 읽는 주체가 사람과 AI 에이전트이므로 거짓 초록불은 게이트를 통째로
# 무력화한다. 판정 로직을 고칠 때 그 두 결함이 조용히 되살아나지 않는지 확인한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-run-suite.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/bin/hooks/run-suite.sh"
FIXTURES="$TESTS_DIR/fixtures-run-suite"

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

echo "=== run-suite.sh 회귀 테스트 ==="

echo "--- 거짓 초록불 회귀 ---"

# 1. 핵심 회귀: 실패인데 출력이 전부 무시 패턴에만 걸리는 경우. 종료 코드 판정으로
#    바뀌기 전에는 여기서 `[✓]` 가 찍혔다.
check "fail-silent (통과 표시 예외)" 1 "exit=1" "[✓]" fail-silent.sh

# 2. 실패 시 원형 로그를 압축하지 않고 보존하는지.
check "fail-verbose (원형 로그 보존)" 1 "FIXTURE_RAW_DETAIL" "-" fail-verbose.sh

echo "--- 무음 스킵 회귀 ---"

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
# run-suite.sh 는 이제 command -v 로 글로벌 명령어를 탐색한다. HOME 만 바꾸면
# PATH 에서 pre-flight-check.sh 를 찾아내 SCRIPTS 가 채워진다. PATH 를 최소화해
# 글로벌 명령어도 찾히지 않게 만들어야 진짜 0건 시나리오를 재현할 수 있다.
OUT=$( (cd "$EMPTY_REPO" && HOME="$TMP" PATH="/usr/bin:/bin" bash "$RUNNER") 2>&1) || CODE=$?
if [ "$CODE" -eq 1 ] && grep -qF "실행할 검증 스크립트를 찾지 못했습니다" <<<"$OUT"; then
  report "대상 0건이면 실패 처리" 0
else
  report "대상 0건이면 실패 처리" 1 "기대 exit=1 + 안내 문구 / 실제 exit=$CODE"
fi

# 9. 8번과 달리 실행 대상(tests/run.sh)은 있는데 3대 게이트(pre-flight-check.sh /
#    prompt-lint.sh / test-coverage-check.sh)만 PATH 에 없는 경우. 이때는 8번의 "대상
#    0건" 가드가 발동하지 않아서, 예전엔 그 게이트들이 아무 말 없이 목록에서 빠진 채
#    남은 스위트만 초록불로 통과했다 — ai_agent 롤이 아직 안 돌아간 새 클론에서
#    `just verify` 가 저장소 전체 스캔·프롬프트 린트·커버리지 게이트를 한 번도 돌리지
#    않고 성공처럼 보이는 경로다(실측: 15개여야 할 대상이 12개로 줄었는데 표시 없음).
#    건너뛴 사실이 반드시 출력에 드러나야 한다.
GATE_REPO="$TMP/dotfiles"
mkdir -p "$GATE_REPO/contexts/probe/tests"
cat >"$GATE_REPO/contexts/probe/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$GATE_REPO/contexts/probe/tests/run.sh"
git -C "$GATE_REPO" init -q
CODE=0
OUT=$( (cd "$GATE_REPO" && HOME="$TMP" PATH="/usr/bin:/bin" bash "$RUNNER") 2>&1) || CODE=$?
if [ "$CODE" -eq 0 ] &&
  grep -qF "[✓] contexts/probe/tests/run.sh" <<<"$OUT" &&
  grep -qF "pre-flight-check.sh" <<<"$OUT" &&
  grep -qF "PATH에 없어 이번 실행에서 수행되지 않았습니다" <<<"$OUT"; then
  report "게이트 미탐지 시 무음 스킵 금지" 0
else
  report "게이트 미탐지 시 무음 스킵 금지" 1 "기대 exit=0 + 건너뜀 경고 / 실제 exit=$CODE out=${OUT//$'\n'/ }"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
