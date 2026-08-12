#!/usr/bin/env bash
# test-verify-bootstrap-env.sh
#
# .github/scripts/verify-bootstrap-env.sh 는 ci.yml 의 bootstrap-smoke job 이
# "bootstrap.sh 가 exit 0 으로 끝났다"를 넘어 README 가 약속한 실제 환경 상태(도구 설치,
# stow 심볼릭 링크, AI 룰/스킬 주입)까지 확인하는 유일한 지점이다. 그런데 이 스크립트는
# test-coverage-check.sh 의 스캔 범위(bin/, stow/git/.githooks/) 밖에 있어 회귀 테스트가
# 없었다.
#
# 이런 "존재를 단언하는" 검증 스크립트의 가장 위험한 고장 방식은 조건을 조용히 잃어버려
# 무엇이 없어도 통과하는 것이다(무검증 통과). 그래서 이 스위트는 통과 경로 하나와
# "필요한 것이 하나씩 빠졌을 때 반드시 실패하는가"를 항목별로 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-verify-bootstrap-env.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
SUT="$REPO_ROOT/.github/scripts/verify-bootstrap-env.sh"

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

# bootstrap.sh 가 만들어 놓았어야 할 홈 디렉토리 상태를 통째로 재현한다.
# mise 는 스텁으로 대체한다. SUT 가 PATH 앞단에 $HOME/.local/bin 을 넣으므로 그 자리에
# 두면 실제 mise 대신 이 스텁이 잡힌다(테스트가 실제 개발 머신 상태에 좌우되지 않게 함).
build_home() {
  local home=$1
  rm -rf "$home"
  mkdir -p "$home/.local/bin" "$home/.local/share/mise/shims" \
    "$home/.config/mise" "$home/.gemini/config/skills/aws" "$home/.claude/skills/aws" \
    "$home/src"

  cat >"$home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
# `mise which <tool>` 만 흉내내는 스텁
[ "${1:-}" = "which" ] && exit 0
exit 0
EOF
  chmod +x "$home/.local/bin/mise"

  # 링크 대상 실체 파일들(내용이 있어야 -s 검사를 통과한다)
  local f
  for f in zshrc gitconfig vimrc tflint.hcl mise-config AGENTS.md CLAUDE.md; do
    echo "content" >"$home/src/$f"
  done

  ln -sf "$home/src/zshrc" "$home/.zshrc"
  ln -sf "$home/src/gitconfig" "$home/.gitconfig"
  ln -sf "$home/src/vimrc" "$home/.vimrc"
  ln -sf "$home/src/tflint.hcl" "$home/.tflint.hcl"
  ln -sf "$home/src/mise-config" "$home/.config/mise/config.toml"
  ln -sf "$home/src/AGENTS.md" "$home/.gemini/config/AGENTS.md"
  ln -sf "$home/src/CLAUDE.md" "$home/.claude/CLAUDE.md"
  # 스킬 레지스트리는 "비어 있지 않음"만 검사하므로 더미 항목 하나면 충분하다.
  echo "x" >"$home/.gemini/config/skills/aws/SKILL.md"
  echo "x" >"$home/.claude/skills/aws/SKILL.md"
}

run_sut() {
  local home=$1 status=0
  HOME="$home" bash "$SUT" >"$TMP/out" 2>&1 || status=$?
  echo "$status"
}

echo "=== verify-bootstrap-env.sh (bootstrap 성공 기준 검증) 회귀 테스트 ==="

FAKE="$TMP/home"

# 1. 모든 조건이 갖춰지면 통과해야 한다(오탐 방지 기준선).
build_home "$FAKE"
status=$(run_sut "$FAKE")
if [ "$status" -eq 0 ]; then
  report "pass-complete-env (완비된 환경은 통과)" 0
else
  report "pass-complete-env (완비된 환경은 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 2. stow 심볼릭 링크가 하나라도 없으면 반드시 실패해야 한다.
#    (조건을 조용히 잃어버려 통과시키는 무검증 통과 방지)
for missing in .zshrc .gitconfig .vimrc .tflint.hcl .config/mise/config.toml; do
  build_home "$FAKE"
  rm -f "$FAKE/$missing"
  status=$(run_sut "$FAKE")
  if [ "$status" -ne 0 ]; then
    report "fail-missing-symlink ($missing 누락 시 차단)" 0
  else
    report "fail-missing-symlink ($missing 누락 시 차단)" 1 "exit=$status"
  fi
done

# 3. AI 글로벌 룰 링크가 없으면 실패해야 한다.
for missing in .gemini/config/AGENTS.md .claude/CLAUDE.md; do
  build_home "$FAKE"
  rm -f "$FAKE/$missing"
  status=$(run_sut "$FAKE")
  if [ "$status" -ne 0 ]; then
    report "fail-missing-ai-rule ($missing 누락 시 차단)" 0
  else
    report "fail-missing-ai-rule ($missing 누락 시 차단)" 1 "exit=$status"
  fi
done

# 4. 링크는 있는데 내용이 비어 있으면(끊긴 링크·빈 파일) 실패해야 한다.
#    링크 존재만 보고 통과시키면 "주입은 됐는데 내용이 없는" 상태를 놓친다.
build_home "$FAKE"
: >"$FAKE/src/AGENTS.md"
status=$(run_sut "$FAKE")
if [ "$status" -ne 0 ]; then
  report "fail-empty-rule-content (AGENTS.md 내용이 비면 차단)" 0
else
  report "fail-empty-rule-content (AGENTS.md 내용이 비면 차단)" 1 "exit=$status"
fi

# 5. 스킬 레지스트리가 비어 있으면 실패해야 한다.
for skills in .gemini/config/skills .claude/skills; do
  build_home "$FAKE"
  rm -rf "${FAKE:?}/$skills"
  mkdir -p "$FAKE/$skills"
  status=$(run_sut "$FAKE")
  if [ "$status" -ne 0 ]; then
    report "fail-empty-skill-registry ($skills 비면 차단)" 0
  else
    report "fail-empty-skill-registry ($skills 비면 차단)" 1 "exit=$status"
  fi
done

# 6. mise 도구 조회가 실패하면(도구 미설치) 실패해야 한다.
build_home "$FAKE"
cat >"$FAKE/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE/.local/bin/mise"
status=$(run_sut "$FAKE")
if [ "$status" -ne 0 ]; then
  report "fail-tool-missing (mise which 실패 시 차단)" 0
else
  report "fail-tool-missing (mise which 실패 시 차단)" 1 "exit=$status"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
