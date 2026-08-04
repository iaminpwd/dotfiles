#!/usr/bin/env bash
# test-test-coverage-check.sh
#
# test-coverage-check.sh 자신은 지금까지 다른 파일들의 주석/echo 라벨에서만
# 우발적으로 이름이 언급됐을 뿐, 자기 자신의 판정 로직(하드 게이트 + 플러그인
# 전용 경고 레이어)을 직접 검증하는 격리 픽스처 테스트가 없었다. 정작 "테스트가
# 없으면 잡아낸다"는 이 도구 자체가 그 규칙의 사각지대에 있었던 셈이다.
#
# 2026-08-05에 추가된 경고 레이어(bin/hooks/plugins/*.sh가 이름만 언급되고 실제
# bash 호출 증거가 없으면 경고)의 두 갈래 탐지 패턴(변수 대입 후 호출 / 직접 인라인
# 호출)이 깨지면, k8s-check.sh처럼 이름만 주석에 있는 플러그인이 다시 "정상"으로
# 오분류될 수 있다. 격리된 가짜 저장소로 하드 게이트와 경고 레이어를 각각 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-test-coverage-check.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
CHECKER="$REPO_ROOT/bin/linters/test-coverage-check.sh"

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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 최소 골격의 가짜 저장소를 구성한다: bin/hooks/plugins/*.sh 1개 + contexts/fake/tests/run.sh 1개.
new_fixture_repo() {
  local root=$1
  mkdir -p "$root/bin/hooks/plugins" "$root/git/.githooks" "$root/contexts/fake/tests"
  git -C "$root" init -q
  echo '#!/usr/bin/env bash
exit 0' >"$root/bin/hooks/plugins/example-check.sh"
  chmod +x "$root/bin/hooks/plugins/example-check.sh"
}

run_checker() {
  local root=$1 status=0
  (cd "$root" && QUIET=0 bash "$CHECKER") >"$TMP/out" 2>&1 || status=$?
  echo "$status"
}

echo "=== test-coverage-check.sh 자기 자신의 판정 로직 회귀 테스트 ==="

# 1. 하드 게이트: bin/ 스크립트 이름이 tests/ 어디에도 없으면 exit 1 + 목록 보고.
R1="$TMP/repo1"
new_fixture_repo "$R1"
echo '#!/usr/bin/env bash' >"$R1/contexts/fake/tests/run.sh"
status=$(run_checker "$R1")
if [ "$status" -eq 1 ] && grep -qF "example-check.sh" "$TMP/out"; then
  report "hard-gate-untested (참조 없는 스크립트는 exit 1 + 목록 보고)" 0
else
  report "hard-gate-untested (참조 없는 스크립트는 exit 1 + 목록 보고)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 2. 하드 게이트 통과: 이름이 어딘가(주석이라도) 언급되면 통과.
R2="$TMP/repo2"
new_fixture_repo "$R2"
echo '# example-check.sh 를 손보면 확인할 것' >"$R2/contexts/fake/tests/run.sh"
status=$(run_checker "$R2")
if [ "$status" -eq 0 ]; then
  report "hard-gate-mentioned (주석 언급만으로도 하드 게이트는 통과)" 0
else
  report "hard-gate-mentioned (주석 언급만으로도 하드 게이트는 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 3. 경고 레이어: 이름만 주석에 있고 실제 bash 호출 증거가 없으면 WARNING (exit 0 유지).
R3="$TMP/repo3"
new_fixture_repo "$R3"
echo '# example-check.sh 와 동일한 방식으로 처리한다' >"$R3/contexts/fake/tests/run.sh"
status=$(run_checker "$R3")
if [ "$status" -eq 0 ] && grep -qF "[WARNING]" "$TMP/out" && grep -qF "bin/hooks/plugins/example-check.sh" "$TMP/out"; then
  report "weak-coverage-warns (주석뿐이면 경고 발생 + exit 0 유지)" 0
else
  report "weak-coverage-warns (주석뿐이면 경고 발생 + exit 0 유지)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 4. 경고 레이어 통과 (패턴 A, 직접 인라인 호출): bash "...example-check.sh" 형태.
R4="$TMP/repo4"
new_fixture_repo "$R4"
cat >"$R4/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
bash "$REPO_ROOT/bin/hooks/plugins/example-check.sh"
EOF
status=$(run_checker "$R4")
if [ "$status" -eq 0 ] && ! grep -qF "example-check.sh" "$TMP/out"; then
  report "direct-invocation-passes (직접 인라인 bash 호출은 경고 없음)" 0
else
  report "direct-invocation-passes (직접 인라인 bash 호출은 경고 없음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 5. 경고 레이어 통과 (패턴 B, 변수 대입 후 호출): 이 저장소 테스트들의 표준 관례.
R5="$TMP/repo5"
new_fixture_repo "$R5"
cat >"$R5/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
EXAMPLE_PLUGIN="$REPO_ROOT/bin/hooks/plugins/example-check.sh"
bash "$EXAMPLE_PLUGIN"
EOF
status=$(run_checker "$R5")
if [ "$status" -eq 0 ] && ! grep -qF "example-check.sh" "$TMP/out"; then
  report "var-then-invoke-passes (변수 대입 후 bash \"\$VAR\" 호출도 경고 없음)" 0
else
  report "var-then-invoke-passes (변수 대입 후 bash \"\$VAR\" 호출도 경고 없음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 6. 경고 레이어 통과 (패턴 B, 들여쓰기된 변수 대입): if/for 블록 안에서 대입되는 경우도
# 잡아야 한다. observability-check.sh 테스트를 추가했을 때 대입문이 require_tool yq
# 블록 안에 들여쓰기돼 있어 ^[A-Za-z_] 앵커가 못 잡는 실사용 버그가 있었다(2026-08-05).
R6="$TMP/repo6"
new_fixture_repo "$R6"
cat >"$R6/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
if true; then
  EXAMPLE_PLUGIN="$REPO_ROOT/bin/hooks/plugins/example-check.sh"
  bash "$EXAMPLE_PLUGIN"
fi
EOF
status=$(run_checker "$R6")
if [ "$status" -eq 0 ] && ! grep -qF "example-check.sh" "$TMP/out"; then
  report "indented-var-then-invoke-passes (들여쓰기된 변수 대입도 경고 없음)" 0
else
  report "indented-var-then-invoke-passes (들여쓰기된 변수 대입도 경고 없음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
