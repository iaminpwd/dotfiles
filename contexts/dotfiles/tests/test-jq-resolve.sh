#!/usr/bin/env bash
# test-jq-resolve.sh
#
# bin/lib/jq-resolve.sh 는 agent-edits-hook.sh(자동 훅)와 merge-agent-hooks.sh(ansible 호출)가
# 공유하는 jq 경로 해석 SSOT다. mise shim은 $HOME 기준으로 설치 위치를 찾기 때문에,
# HOME을 격리 디렉토리로 덮어쓰는 환경(픽스처 테스트 등)에서는 PATH의 jq가 조용히
# 먹통이 될 수 있다. 이 폴백이 깨지면 두 소비자가 "jq 없음"으로 오판해 조용히
# no-op 하게 된다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-jq-resolve.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/bin/lib/jq-resolve.sh"

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

echo "--- jq-resolve.sh 공용 라이브러리 (SSOT) ---"

# 1. 라이브러리 계약: source 하면 resolve_jq 함수가 정의되어야 한다.
code=0
bash -c 'set -euo pipefail
  source "$1"
  declare -F resolve_jq >/dev/null' _ "$LIB" || code=$?
if [ "$code" -eq 0 ]; then
  report "resolve_jq 함수 제공" 0
else
  report "resolve_jq 함수 제공" 1 "exit=$code"
fi

# 2. 정상 환경(PATH의 jq가 멀쩡함): 실행 가능한 jq 경로를 반환해야 한다.
out=$(bash -c 'source "$1"; resolve_jq' _ "$LIB")
if [ -n "$out" ] && "$out" --version >/dev/null 2>&1; then
  report "정상 환경 -> 실행 가능한 jq 경로 반환" 0
else
  report "정상 환경 -> 실행 가능한 jq 경로 반환" 1 "resolved='$out'"
fi

# 3. mise shim이 HOME 격리로 먹통이 되는 환경: mise 설치 디렉토리를 직접 뒤져서라도
#    실행 가능한 jq를 찾아내야 한다(MISE_DATA_DIR을 명시해 실제 설치 위치는 유지).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_MISE_DATA_DIR="$HOME/.local/share/mise"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"
out=$(MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash -c 'source "$1"; resolve_jq' _ "$LIB")
if [ -n "$out" ] && "$out" --version >/dev/null 2>&1; then
  report "HOME 격리 + MISE_DATA_DIR 지정 -> 여전히 실행 가능한 jq 반환" 0
else
  report "HOME 격리 + MISE_DATA_DIR 지정 -> 여전히 실행 가능한 jq 반환" 1 "resolved='$out'"
fi

# 3b. 폴백 경로 자체의 검증. 위 3번은 MISE_DATA_DIR 을 실제 위치로 넘기는 순간 shim 이
#     정상 동작해 첫 경로(command -v jq)에서 해결되므로, 이름과 달리 폴백을 한 번도 타지
#     않는다 — 실제로 find 폴백을 통째로 지워도 위 케이스는 통과했다(뮤테이션으로 확인).
#     폴백을 태우려면 "PATH 에 jq 는 있는데 실행이 안 되는" 상태를 만들어야 한다.
FAKE_BIN="$TMP/fakebin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/jq" <<'EOF'
#!/usr/bin/env bash
# mise shim 이 해석에 실패해 먹통이 된 상황을 재현한다(어떤 인자로도 실패).
exit 127
EOF
chmod +x "$FAKE_BIN/jq"
out=$(PATH="$FAKE_BIN:$PATH" bash -c 'source "$1"; resolve_jq' _ "$LIB")
if [ -n "$out" ] && [ "$out" != "$FAKE_BIN/jq" ] && "$out" --version >/dev/null 2>&1; then
  report "PATH 의 jq 가 먹통 -> mise 설치 디렉토리 폴백으로 발견" 0
else
  report "PATH 의 jq 가 먹통 -> mise 설치 디렉토리 폴백으로 발견" 1 "resolved='$out' (먹통 shim 을 그대로 반환했거나 폴백이 비었습니다)"
fi

# 4. 소비자(agent-edits-hook.sh, merge-agent-hooks.sh)가 옛 인라인 로직을 되살리지 않았는지 확인한다.
CONSUMERS=(
  "$REPO_ROOT/bin/hooks/agent-edits-hook.sh"
  "$REPO_ROOT/bin/utils/merge-agent-hooks.sh"
)
dup=0
for consumer in "${CONSUMERS[@]}"; do
  grep -qF "jq-resolve.sh" "$consumer" || dup=1
  grep -qE '^JQ=\$\(command -v jq' "$consumer" && dup=1
done
if [ "$dup" -eq 0 ]; then
  report "소비자가 공용 라이브러리를 실제로 source하고 인라인 복제를 안 함" 0
else
  report "소비자가 공용 라이브러리를 실제로 source하고 인라인 복제를 안 함" 1 "복제본이 되살아났거나 source가 빠졌습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
