#!/usr/bin/env bash
# test-pre-flight-live-hook.sh
#
# pre-flight-live-hook.sh는 PostToolUse 훅으로 조용히 실행되고(-e 미사용, 실패해도
# exit 0), 대상 저장소 판정·확장자 제외·성공/실패 시 JSON 출력 로직이 깨져도 아무도
# 눈치채지 못한다. 실제 pre-flight-check.sh(무거운 외부 도구 의존)를 돌리는 대신,
# 격리된 픽스처 저장소 루트에 성공/실패를 흉내내는 스텁을 놓아 훅 자체의 판정
# 로직만 고정한다. 이 훅은 run-suite.sh를 거치므로(옵트인 저장소는 훅 자신의 물리적
# 위치에서 구한 정본 run-suite.sh로 폴백) 성공 시에도 decision 없이
# additionalContext에 압축된 "-> [✓]" 한 줄이 실리는지, 실패 시엔 decision:block이
# 걸리는지를 함께 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-pre-flight-live-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/bin/hooks/pre-flight-live-hook.sh"

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

FIXTURE_REPO="$TMP/fixture-repo"
mkdir -p "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" init -q

# 루트에 옵트인 pre-flight-check.sh 스텁을 두면(git/.githooks/pre-commit과 동일한
# 옵트인 규약) dotfiles/~/workspace가 아니어도 훅이 이 저장소를 대상으로 삼는다.
stub_pass() {
  cat >"$FIXTURE_REPO/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FIXTURE_REPO/pre-flight-check.sh"
}
stub_fail() {
  cat >"$FIXTURE_REPO/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
echo "STUB_VALIDATION_FAILURE: $1"
exit 1
EOF
  chmod +x "$FIXTURE_REPO/pre-flight-check.sh"
}

echo "=== pre-flight-live-hook.sh 판정 로직 회귀 테스트 ==="

# 1. 검증 통과(exit 0) 시 decision 없이 additionalContext에 run-suite.sh의 압축된
#    "-> [✓]" 한 줄이 실려야 한다(차단·재응답은 없음 = decision 필드 자체가 없음).
stub_pass
echo "ok" >"$FIXTURE_REPO/ok.sh"
payload1="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIXTURE_REPO/ok.sh\"}}"
out1=$(echo "$payload1" | bash "$HOOK")
if echo "$out1" | jq -e 'has("decision") | not' >/dev/null 2>&1 &&
  echo "$out1" | jq -e '.hookSpecificOutput.additionalContext | contains("[✓]")' >/dev/null 2>&1; then
  report "검증 통과 (decision 없이 압축 로그만)" 0
else
  report "검증 통과 (decision 없이 압축 로그만)" 1 "out=$out1"
fi

# 2. 검증 실패(exit 1) 시 decision:block JSON과 스텁 출력이 additionalContext에 담겨야 한다.
stub_fail
echo "bad" >"$FIXTURE_REPO/bad.sh"
payload2="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIXTURE_REPO/bad.sh\"}}"
out2=$(echo "$payload2" | bash "$HOOK")
if echo "$out2" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
  echo "$out2" | jq -e '.reason | contains("bad.sh")' >/dev/null 2>&1 &&
  echo "$out2" | jq -e '.hookSpecificOutput.additionalContext | contains("STUB_VALIDATION_FAILURE")' >/dev/null 2>&1; then
  report "검증 실패 (decision:block JSON)" 0
else
  report "검증 실패 (decision:block JSON)" 1 "out=$out2"
fi

# 3. .tf는 스텁이 항상 실패하도록 해놔도 네트워크/빌드 의존 확장자 제외 로직으로
#    조용히 건너뛰어야 한다(스텁조차 호출되지 않음).
echo "resource" >"$FIXTURE_REPO/main.tf"
payload3="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIXTURE_REPO/main.tf\"}}"
out3=$(echo "$payload3" | bash "$HOOK")
if [ -z "$out3" ]; then
  report ".tf 확장자 제외 (건너뜀)" 0
else
  report ".tf 확장자 제외 (건너뜀)" 1 "out=$out3"
fi

# 4. Antigravity 스키마(toolCall.args.TargetFile)도 동일하게 판정되어야 한다.
payload4="{\"toolCall\":{\"name\":\"replace_file_content\",\"args\":{\"TargetFile\":\"$FIXTURE_REPO/bad.sh\"}}}"
out4=$(echo "$payload4" | bash "$HOOK")
if echo "$out4" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  report "antigravity-schema (TargetFile 판정)" 0
else
  report "antigravity-schema (TargetFile 판정)" 1 "out=$out4"
fi

# 5. 옵트인 대상이 아닌 저장소(루트에 pre-flight-check.sh 없음)는 조용히 건너뛰어야 한다.
UNSCOPED_REPO="$TMP/unscoped-repo"
mkdir -p "$UNSCOPED_REPO"
git -C "$UNSCOPED_REPO" init -q
echo "bad" >"$UNSCOPED_REPO/bad.sh"
payload5="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$UNSCOPED_REPO/bad.sh\"}}"
out5=$(echo "$payload5" | bash "$HOOK")
if [ -z "$out5" ]; then
  report "옵트인 대상 아닌 저장소 (건너뜀)" 0
else
  report "옵트인 대상 아닌 저장소 (건너뜀)" 1 "out=$out5"
fi

# 5b. 실행 권한이 없는 옵트인 스크립트도 검증 대상으로 잡아야 한다.
#     이 훅은 pfc 를 직접 실행하지 않고 run-suite.sh 에 인자로 넘기며, run-suite 는
#     `[ -f "$script" ]` 이면 `bash "$script"` 로 돌리므로 실행 권한이 필요 없다.
#     예전엔 -x 로 판정해 복사본을 실행 권한 없이 배치한 옵트인 저장소에서 이 훅만
#     조용히 exit 0 했는데, 정작 git/.githooks/pre-commit 은 -f 라 같은 저장소를
#     검증하고 있었다 — 헤더 주석이 두 로직을 "동일하게 맞췄다"고 선언한 것과 어긋난
#     상태였다(실측 재현). 무음 스킵은 이 저장소가 반복해서 제거해 온 실패 형태다.
NOEXEC_REPO="$TMP/noexec-optin"
mkdir -p "$NOEXEC_REPO"
git -C "$NOEXEC_REPO" init -q
cat >"$NOEXEC_REPO/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
echo "STUB_VALIDATION_FAILURE: no-exec-optin"
exit 1
EOF
chmod -x "$NOEXEC_REPO/pre-flight-check.sh"
echo "bad" >"$NOEXEC_REPO/bad.sh"
payload5b="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$NOEXEC_REPO/bad.sh\"}}"
out5b=$(echo "$payload5b" | bash "$HOOK")
if grep -qF '"decision": "block"' <<<"$out5b" && grep -qF 'STUB_VALIDATION_FAILURE' <<<"$out5b"; then
  report "실행 권한 없는 옵트인 (검증 수행, 무음 스킵 아님)" 0
else
  report "실행 권한 없는 옵트인 (검증 수행, 무음 스킵 아님)" 1 "out=$out5b"
fi

# 6. 편집 대상이 없는 조회 도구 호출은 조용히 건너뛰어야 한다.
payload6='{"tool_name":"Read","tool_input":{}}'
out6=$(echo "$payload6" | bash "$HOOK")
if [ -z "$out6" ]; then
  report "read-only 호출 (건너뜀)" 0
else
  report "read-only 호출 (건너뜀)" 1 "out=$out6"
fi

# 7. 정본 저장소 경로를 $HOME 기준으로 하드코딩하지 않아야 한다.
#    예전 폴백은 "$HOME/dotfiles/bin/..." 이었는데, 저장소가 그 경로에 없으면(CI 체크아웃
#    경로 ~/work/dotfiles/dotfiles, 여러 벌 클론, ~/src/dotfiles 같은 개인 배치) 존재하지
#    않는 파일을 가리켜 훅이 `[ -x "$rs" ] || exit 0` 에 걸려 조용히 빠졌다. 개발 머신에서는
#    마침 ~/dotfiles 라 우연히 통과하고 CI 에서만 실패했다(실측).
#    행동으로 재현하려면 HOME 을 임시 디렉토리로 바꿔야 하는데, 그러면 mise shim 이 도구를
#    그 임시 홈에 통째로 새로 설치해 버려(네트워크 의존 + 매 실행 재설치) 스위트가 느리고
#    불안정해진다 — 실측으로 확인해 그 방식은 택하지 않았다. 대신 같은 패턴이 소스에 다시
#    들어오는 것을 정적으로 막는다.
hook_code=$(grep -vE '^[[:space:]]*#' "$HOOK" || true)
# 홑따옴표가 맞다: 셸이 전개한 값이 아니라 소스에 적힌 리터럴 문자열을 찾는 검사다.
# shellcheck disable=SC2016
if grep -qF '$HOME/dotfiles' <<<"$hook_code"; then
  report "정본 경로를 \$HOME 기준으로 하드코딩하지 않음" 1 "$(grep -nF '$HOME/dotfiles' "$HOOK")"
else
  report "정본 경로를 \$HOME 기준으로 하드코딩하지 않음" 0
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
