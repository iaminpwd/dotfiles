#!/usr/bin/env bash
# test-test-coverage-check.sh
#
# test-coverage-check.sh 자신은 지금까지 다른 파일들의 주석/echo 라벨에서만
# 우발적으로 이름이 언급됐을 뿐, 자기 자신의 판정 로직(하드 게이트 + 플러그인
# 전용 경고 레이어)을 직접 검증하는 격리 픽스처 테스트가 없었다. 정작 "테스트가
# 없으면 잡아낸다"는 이 도구 자체가 그 규칙의 사각지대에 있었던 셈이다.
#
# 경고 레이어(bin/hooks/plugins/*.sh가 이름만 언급되고 실제 bash 호출 증거가 없으면
# 경고)의 두 갈래 탐지 패턴(변수 대입 후 호출 / 직접 인라인 호출)이 깨지면,
# k8s-check.sh처럼 이름만 주석에 있는 플러그인이 다시 "정상"으로 오분류될 수 있다.
# 격리된 가짜 저장소로 하드 게이트와 경고 레이어를 각각 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-test-coverage-check.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

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
  mkdir -p "$root/bin/hooks/plugins" "$root/bin/linters" "$root/bin/lib" "$root/stow/git/.githooks" "$root/contexts/fake/tests"
  git -C "$root" init -q
  echo '#!/usr/bin/env bash
exit 0' >"$root/bin/hooks/plugins/example-check.sh"
  chmod +x "$root/bin/hooks/plugins/example-check.sh"
  # test-coverage-check.sh는 자기 자신의 물리적 위치를 기준으로 REPO_ROOT를 고정한다
  # (CWD 비의존). 격리 픽스처로 테스트하려면 실제 스크립트와 그 의존 라이브러리를
  # 같은 상대 위치(bin/linters/, bin/lib/)로 함께 복사해야 한다(test-pre-push-hook.sh가
  # run-suite.sh를 다루는 방식과 동일한 이유).
  cp "$REPO_ROOT/bin/linters/test-coverage-check.sh" "$root/bin/linters/test-coverage-check.sh"
  cp "$REPO_ROOT/bin/lib/script-init.sh" "$root/bin/lib/script-init.sh"
  # 복사해 넣은 script-init.sh도 하드 게이트 대상이므로, 각 테스트 케이스의 run.sh와
  # 별개로 이 커버리지를 항상 충족시켜 example-check.sh 판정만 순수하게 검증한다.
  echo "# script-init.sh" >"$root/contexts/fake/tests/lib-coverage.txt"
}

run_checker() {
  local root=$1 status=0
  (cd "$root" && QUIET=0 bash "$root/bin/linters/test-coverage-check.sh") >"$TMP/out" 2>&1 || status=$?
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
# 잡아야 한다. 대입문이 require_tool yq 같은 블록 안에 들여쓰기돼 있으면 ^[A-Za-z_]
# 앵커가 못 잡는 실사용 버그가 생길 수 있다.
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

# 7. 등록 누락 하드 게이트: tests/ 에 테스트 파일이 있는데 run.sh 목록에 없으면 exit 1.
#    (실제로 test-pre-flight-live-hook.sh / test-pre-flight-gate-hook.sh 가 이 상태로
#     한 번도 실행되지 않았는데 위 1번 게이트는 통과했다 — 그 사각지대를 고정한다.)
R7="$TMP/repo7"
new_fixture_repo "$R7"
echo '# example-check.sh 를 손보면 확인할 것' >"$R7/contexts/fake/tests/run.sh"
echo '#!/usr/bin/env bash' >"$R7/contexts/fake/tests/test-orphan.sh"
status=$(run_checker "$R7")
if [ "$status" -eq 1 ] && grep -qF "test-orphan.sh" "$TMP/out" && grep -qF "등록되지 않아" "$TMP/out"; then
  report "unregistered-suite-blocks (run.sh 미등록 테스트는 exit 1 + 목록 보고)" 0
else
  report "unregistered-suite-blocks (run.sh 미등록 테스트는 exit 1 + 목록 보고)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 8. 등록돼 있으면 통과한다(정상 경로가 막히지 않는지 확인).
R8="$TMP/repo8"
new_fixture_repo "$R8"
cat >"$R8/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
# example-check.sh 를 손보면 확인할 것
for suite in test-orphan; do
  bash "$suite.sh"
done
EOF
echo '#!/usr/bin/env bash' >"$R8/contexts/fake/tests/test-orphan.sh"
status=$(run_checker "$R8")
if [ "$status" -eq 0 ] && ! grep -qF "등록되지 않아" "$TMP/out"; then
  report "registered-suite-passes (run.sh 에 등록된 테스트는 통과)" 0
else
  report "registered-suite-passes (run.sh 에 등록된 테스트는 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 9. 언더스코어 명명(test_*.sh)도 같은 게이트 대상이어야 한다. 이 저장소에는
#    contexts/prompt-architect/tests/test_prompt_lint.sh 가 실재하므로, test-*.sh 로만
#    좁히면 이 게이트가 막으려는 것과 같은 사각지대가 새로 생긴다.
R9="$TMP/repo9"
new_fixture_repo "$R9"
echo '# example-check.sh 를 손보면 확인할 것' >"$R9/contexts/fake/tests/run.sh"
echo '#!/usr/bin/env bash' >"$R9/contexts/fake/tests/test_underscore.sh"
status=$(run_checker "$R9")
if [ "$status" -eq 1 ] && grep -qF "test_underscore.sh" "$TMP/out"; then
  report "underscore-named-suite-blocks (test_*.sh 도 등록 게이트 대상)" 0
else
  report "underscore-named-suite-blocks (test_*.sh 도 등록 게이트 대상)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 10. 진입점(run.sh) 자체가 없으면 스위트가 통째로 안 도는 것이므로 별도 메시지로 차단한다.
#     원인과 조치가 "목록에 추가"와 다르기 때문에 등록 누락과 구분해 보고한다.
R10="$TMP/repo10"
new_fixture_repo "$R10"
rm -f "$R10/contexts/fake/tests/run.sh"
# run.sh 가 없으므로 1번 게이트용 example-check.sh 언급은 테스트 파일 쪽에 둔다.
echo '# example-check.sh 를 손보면 확인할 것' >"$R10/contexts/fake/tests/test-no-runner.sh"
status=$(run_checker "$R10")
if [ "$status" -eq 1 ] && grep -qF "진입점(run.sh)이 없어" "$TMP/out"; then
  report "missing-runner-blocks (run.sh 부재는 별도 메시지로 exit 1)" 0
else
  report "missing-runner-blocks (run.sh 부재는 별도 메시지로 exit 1)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 11. 주석에만 이름이 있으면 등록으로 치지 않는다. 이 게이트를 처음 넣은 직후 실제로
#     run.sh 에 설명 주석을 추가했더니 등록을 빼도 통과해 버렸다(게이트 무력화 실측).
R11="$TMP/repo11"
new_fixture_repo "$R11"
cat >"$R11/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
# example-check.sh 를 손보면 확인할 것
# 참고: test-orphan 스위트는 아래 목록에서 잠시 뺀 상태다
for suite in ; do
  bash "$suite.sh"
done
EOF
echo '#!/usr/bin/env bash' >"$R11/contexts/fake/tests/test-orphan.sh"
status=$(run_checker "$R11")
if [ "$status" -eq 1 ] && grep -qF "test-orphan.sh" "$TMP/out"; then
  report "comment-only-mention-blocks (주석 언급은 등록으로 치지 않음)" 0
else
  report "comment-only-mention-blocks (주석 언급은 등록으로 치지 않음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 12~13. SKIP 안내 가시성 게이트.
#
# 등록된 테스트가 도구 부재로 케이스를 건너뛰면 스위트는 그대로 exit 0 이고,
# run-suite.sh 는 통과한 스크립트의 출력에서 [WARNING]/⚠ 로 시작하는 줄만 남기고 나머지를
# 버린다. 그래서 "  SKIP ..." 안내는 just verify·CI·pre-push·Stop 게이트 훅 어디에서도
# 보이지 않고 "-> [✓]" 한 줄만 남는다(실측: trufflehog 없는 환경에서 시크릿 스캔 회귀
# 2건이 통째로 건너뛰어졌는데 출력에 아무 표시가 없었다). 존재·등록에 이은 세 번째 고리다.

# 12. 접두사 없는 SKIP 안내는 차단해야 한다.
R12="$TMP/repo12"
new_fixture_repo "$R12"
cat >"$R12/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
# example-check.sh 를 손보면 확인할 것
for suite in test-skip; do
  bash "$suite.sh"
done
EOF
# 위반 픽스처는 반드시 동적으로 조립한다. 힙독에 그대로 써 넣으면 이 테스트 파일 자신이
# contexts/*/tests/*.sh 라 게이트의 스캔 대상이 되어, 자기 픽스처를 실제 위반으로 신고하며
# just verify 를 깨뜨린다(실측: 이 케이스를 힙독으로 처음 넣었을 때 그대로 발생했다).
# printf 로 조립하면 이 파일 어디에도 위반 형태의 리터럴이 남지 않는다.
{
  echo '#!/usr/bin/env bash'
  printf 'echo "  %s  some-case (도구 미설치)"\n' "SKIP"
} >"$R12/contexts/fake/tests/test-skip.sh"
status=$(run_checker "$R12")
if [ "$status" -eq 1 ] && grep -qF "test-skip.sh" "$TMP/out" && grep -qF "압축 필터" "$TMP/out"; then
  report "skip-without-warning-prefix-blocks (접두사 없는 SKIP 안내 차단)" 0
else
  report "skip-without-warning-prefix-blocks (접두사 없는 SKIP 안내 차단)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 13. [WARNING] 로 시작하면 통과해야 한다(오탐 축). 주석에 SKIP 이 스쳐도 마찬가지다 —
#     스위트 헤더의 "도구 미설치는 SKIP 이 아니라 실패로 처리한다" 같은 문장이 실제로 있다.
R13="$TMP/repo13"
new_fixture_repo "$R13"
cat >"$R13/contexts/fake/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
# example-check.sh 를 손보면 확인할 것
for suite in test-skip; do
  bash "$suite.sh"
done
EOF
cat >"$R13/contexts/fake/tests/test-skip.sh" <<'EOF'
#!/usr/bin/env bash
# 도구 미설치는 SKIP 이 아니라 실패로 처리한다는 설명 주석
echo "[WARNING] SKIP some-case — 도구 미설치로 이 회귀가 수행되지 않았습니다"
EOF
status=$(run_checker "$R13")
if [ "$status" -eq 0 ]; then
  report "skip-with-warning-prefix-passes ([WARNING] 접두사와 주석은 오탐 없음)" 0
else
  report "skip-with-warning-prefix-passes ([WARNING] 접두사와 주석은 오탐 없음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
