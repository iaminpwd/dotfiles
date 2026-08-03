#!/usr/bin/env bash
# test-detector-logic.sh
#
# check-symlinks.sh는 실제 개발 머신의 $HOME을 그대로 스캔한다 — 이건 "지금 이
# 머신에 깨진 링크가 있는가"라는 실사용 점검으로는 유효하지만, 탐지 로직 자체가
# 맞는지는 증명하지 못한다. $HOME에 우연히 깨진 링크가 하나도 없으면 탐지 로직이
# 완전히 죽어 있어도(예: find 조건이 항상 거짓) 조용히 통과한다.
#
# broken-symlink-detector.sh는 $HOME을 인자로 받지 않고 하드코딩해서 읽으므로,
# HOME 환경변수를 격리된 픽스처 디렉토리로 덮어써서 테스트한다
# (contexts/pre-flight-check/tests/run.sh의 EMPTY_REPO 검사와 동일한 관용구).
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-detector-logic.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
DETECTOR="$REPO_ROOT/bin/utils/broken-symlink-detector.sh"

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

echo "=== broken-symlink-detector.sh 탐지 로직 회귀 테스트 ==="

# 1. 정상 케이스: 유효한 대상을 가리키는 심볼릭 링크만 있으면 통과해야 한다.
OK_HOME="$TMP/ok-baseline"
mkdir -p "$OK_HOME/.config"
echo "real file" >"$OK_HOME/.config/real-target"
ln -s "$OK_HOME/.config/real-target" "$OK_HOME/.zshrc"

status=0
out=$(HOME="$OK_HOME" bash "$DETECTOR" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-baseline (유효한 링크만 있으면 통과)" 0
else
  report "ok-baseline (유효한 링크만 있으면 통과)" 1 "기대 exit=0 / 실제 exit=$status: $out"
fi

# 2. 위반 케이스: 대상이 없는 깨진 링크가 depth 2 이내에 있으면 차단해야 한다.
FAIL_HOME="$TMP/fail-broken-link"
mkdir -p "$FAIL_HOME/.config"
ln -s "$FAIL_HOME/.config/does-not-exist" "$FAIL_HOME/.config/broken-link"

status=0
out=$(HOME="$FAIL_HOME" bash "$DETECTOR" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "$FAIL_HOME/.config/broken-link" <<<"$out"; then
  report "fail-broken-link (깨진 링크 경로까지 보고)" 0
else
  report "fail-broken-link (깨진 링크 경로까지 보고)" 1 "기대 exit=1 + 깨진 링크 경로 포함 / 실제 exit=$status: $out"
fi

# 3. depth 경계: maxdepth 2를 벗어난(3단계 이상 하위) 깨진 링크는 잡지 않는 것이
#    현재 구현의 명시된 동작이다("~/ 디렉토리 기준 depth 2까지"). 이 경계가 조용히
#    넓어지거나 좁아지면(find 옵션 오타 등) 여기서 드러난다.
DEPTH_HOME="$TMP/ok-beyond-depth"
mkdir -p "$DEPTH_HOME/.config/nested"
ln -s "$DEPTH_HOME/.config/nested/does-not-exist" "$DEPTH_HOME/.config/nested/broken-link"

status=0
out=$(HOME="$DEPTH_HOME" bash "$DETECTOR" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-beyond-depth (maxdepth 2 밖은 스캔하지 않음)" 0
else
  report "ok-beyond-depth (maxdepth 2 밖은 스캔하지 않음)" 1 "기대 exit=0 / 실제 exit=$status: $out"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
