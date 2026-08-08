#!/usr/bin/env bash
# test-pre-flight-gate-hook.sh
#
# pre-flight-gate-hook.sh는 Stop 훅으로 조용히 실행되고(-e 미사용), 변경사항 존재 여부
# 판정·저장소 스코프 판정·stop_hook_active 무한루프 방지·검사 3종 조합 로직이 깨져도
# 아무도 눈치채지 못한다. 실제 pre-flight-check.sh/prompt-lint.sh/test-coverage-check.sh
# (무거운 외부 도구·전체 코퍼스 스캔 의존) 대신, 성공/실패를 흉내내는 스텁으로 훅 자체의
# 판정 로직만 고정한다. 이 훅은 3개를 run-suite.sh 경유로 돌리므로(test-pre-push-hook.sh와
# 동일 이유로 무거운 외부 도구를 타지 않도록) dotfiles 픽스처에 실제 run-suite.sh/
# script-init.sh를 그대로 복사해 넣는다. 성공 시에도 decision 없이 additionalContext에
# run-suite.sh의 압축된 "-> [✓]" 로그가 실리는지(=훅이 애초에 안 돈 것과 구분되는지),
# 실패 시엔 decision:block이 걸리는지를 함께 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-pre-flight-gate-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/bin/hooks/pre-flight-gate-hook.sh"

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

stub() {
  local path=$1 rc=$2 marker=$3
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
echo "$marker"
exit $rc
EOF
  chmod +x "$path"
}

git_init_clean() {
  local repo=$1
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  echo x >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" -c core.hooksPath=/dev/null commit -q -m "chore: 초기 커밋"
}

payload() {
  local cwd=$1 active=${2:-false}
  printf '{"cwd":"%s","stop_hook_active":%s}' "$cwd" "$active"
}

echo "=== pre-flight-gate-hook.sh 판정 로직 회귀 테스트 ==="

# --- 픽스처 1: basename이 "dotfiles"인 저장소 (prompt-lint/test-coverage-check까지 대상) ---
DOTFILES_REPO="$TMP/dotfiles"
git_init_clean "$DOTFILES_REPO"
mkdir -p "$DOTFILES_REPO/bin/hooks" "$DOTFILES_REPO/bin/lib"
cp "$REPO_ROOT/bin/hooks/run-suite.sh" "$DOTFILES_REPO/bin/hooks/run-suite.sh"
chmod +x "$DOTFILES_REPO/bin/hooks/run-suite.sh"
cp "$REPO_ROOT/bin/lib/script-init.sh" "$DOTFILES_REPO/bin/lib/script-init.sh"
stub "$DOTFILES_REPO/bin/hooks/pre-flight-check.sh" 0 "PFC_OK"
stub "$DOTFILES_REPO/bin/linters/prompt-lint.sh" 0 "LINT_OK"
stub "$DOTFILES_REPO/bin/linters/test-coverage-check.sh" 0 "COVERAGE_OK"
# 스텁 자체가 untracked 상태로 남으면 "변경사항 없음" 테스트가 거짓으로 실패하므로,
# 스텁을 저장소의 커밋된 베이스라인으로 편입한다.
git -C "$DOTFILES_REPO" add -A
git -C "$DOTFILES_REPO" -c core.hooksPath=/dev/null commit -q -m "chore: 검증 스텁 추가"

# 1. 변경사항이 전혀 없으면(클린 상태) 아무 것도 실행하지 않고 조용히 빠져야 한다.
out1=$(payload "$DOTFILES_REPO" | bash "$HOOK")
if [ -z "$out1" ]; then
  report "변경사항 없음 (건너뜀)" 0
else
  report "변경사항 없음 (건너뜀)" 1 "out=$out1"
fi

# 2. 변경사항이 있고 3종 스텁이 전부 통과하면 decision 없이 압축 로그 3줄이 실려야 한다.
echo "dirty" >>"$DOTFILES_REPO/README.md"
out2=$(payload "$DOTFILES_REPO" | bash "$HOOK")
if echo "$out2" | jq -e 'has("decision") | not' >/dev/null 2>&1 &&
  echo "$out2" | jq -e '[.hookSpecificOutput.additionalContext | scan("\\[✓\\]")] | length == 3' >/dev/null 2>&1; then
  report "3종 전부 통과 (decision 없이 압축 로그 3줄)" 0
else
  report "3종 전부 통과 (decision 없이 압축 로그 3줄)" 1 "out=$out2"
fi

# 3. pre-flight-check.sh가 실패하면 decision:block + 스텁 마커가 additionalContext에 담겨야 한다.
stub "$DOTFILES_REPO/bin/hooks/pre-flight-check.sh" 1 "PFC_FAIL_MARKER"
out3=$(payload "$DOTFILES_REPO" | bash "$HOOK")
if echo "$out3" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
  echo "$out3" | jq -e '.hookSpecificOutput.additionalContext | contains("PFC_FAIL_MARKER")' >/dev/null 2>&1; then
  report "pre-flight-check 실패 (decision:block)" 0
else
  report "pre-flight-check 실패 (decision:block)" 1 "out=$out3"
fi
stub "$DOTFILES_REPO/bin/hooks/pre-flight-check.sh" 0 "PFC_OK"

# 4. prompt-lint.sh가 실패하면(pre-flight-check는 통과) 그 마커가 담겨야 한다
#    (dotfiles 저장소에서만 도는 코퍼스 전역 검사가 실제로 호출되는지 확인).
stub "$DOTFILES_REPO/bin/linters/prompt-lint.sh" 1 "LINT_FAIL_MARKER"
out4=$(payload "$DOTFILES_REPO" | bash "$HOOK")
if echo "$out4" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
  echo "$out4" | jq -e '.hookSpecificOutput.additionalContext | contains("LINT_FAIL_MARKER")' >/dev/null 2>&1; then
  report "prompt-lint 실패 (decision:block)" 0
else
  report "prompt-lint 실패 (decision:block)" 1 "out=$out4"
fi
stub "$DOTFILES_REPO/bin/linters/prompt-lint.sh" 0 "LINT_OK"

# 5. stop_hook_active=true면 무한루프 방지를 위해 실패해도 조용히 통과해야 한다.
stub "$DOTFILES_REPO/bin/hooks/pre-flight-check.sh" 1 "PFC_FAIL_MARKER"
out5=$(payload "$DOTFILES_REPO" true | bash "$HOOK")
if [ -z "$out5" ]; then
  report "stop_hook_active=true (무한루프 방지, 조용히 통과)" 0
else
  report "stop_hook_active=true (무한루프 방지, 조용히 통과)" 1 "out=$out5"
fi
stub "$DOTFILES_REPO/bin/hooks/pre-flight-check.sh" 0 "PFC_OK"

# --- 픽스처 2: 옵트인 일반 저장소 (루트에 pre-flight-check.sh만 있음, prompt-lint 등 대상 아님) ---
OPTIN_REPO="$TMP/some-project"
git_init_clean "$OPTIN_REPO"
stub "$OPTIN_REPO/pre-flight-check.sh" 1 "OPTIN_FAIL_MARKER"
echo "dirty" >>"$OPTIN_REPO/README.md"
out6=$(payload "$OPTIN_REPO" | bash "$HOOK")
if echo "$out6" | jq -e '.hookSpecificOutput.additionalContext | contains("OPTIN_FAIL_MARKER")' >/dev/null 2>&1 &&
  ! echo "$out6" | grep -qF "LINT_"; then
  report "옵트인 저장소 (pre-flight-check만 대상, prompt-lint 미실행)" 0
else
  report "옵트인 저장소 (pre-flight-check만 대상, prompt-lint 미실행)" 1 "out=$out6"
fi

# --- 픽스처 3: 스코프 밖 저장소 (pre-flight-check.sh 어디에도 없음) ---
UNSCOPED_REPO="$TMP/unscoped-repo"
git_init_clean "$UNSCOPED_REPO"
echo "dirty" >>"$UNSCOPED_REPO/README.md"
out7=$(payload "$UNSCOPED_REPO" | bash "$HOOK")
if [ -z "$out7" ]; then
  report "스코프 밖 저장소 (건너뜀)" 0
else
  report "스코프 밖 저장소 (건너뜀)" 1 "out=$out7"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
