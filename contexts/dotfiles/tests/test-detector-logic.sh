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

# 3. 실제 설치 대상 깊이가 사정권 안에 있어야 한다.
#
#    예전 이 케이스는 "maxdepth 2 밖은 스캔하지 않음"을 정상 동작으로 고정하고 있었다.
#    그런데 그 경계 밖에 정작 이 저장소가 링크를 심는 곳이 전부 있었다 —
#    ~/.local/bin/<script>.sh(깊이 3), ~/.claude/skills/<skill>/SKILL.md(깊이 4),
#    ~/.gemini/config/skills/<skill>/<file>(깊이 5).
#    실측: 폐기 스킬을 지운 뒤 ~/.local/bin 에 남은 깨진 링크 3개를 탐지기가 "0건"으로
#    보고했다. 테스트가 결함을 사양으로 못 박고 있었던 셈이라, 경계를 설치 대상 기준으로
#    다시 잡는다.
for depth_case in ".local/bin:3" ".claude/skills/demo:4" ".gemini/config/skills/demo:5"; do
  rel="${depth_case%%:*}"
  depth="${depth_case##*:}"
  DEPTH_HOME="$TMP/fail-depth-$depth"
  mkdir -p "$DEPTH_HOME/$rel"
  ln -s "$DEPTH_HOME/$rel/does-not-exist" "$DEPTH_HOME/$rel/broken-link"

  status=0
  out=$(HOME="$DEPTH_HOME" bash "$DETECTOR" 2>&1) || status=$?
  if [ "$status" -eq 1 ] && grep -qF "$DEPTH_HOME/$rel/broken-link" <<<"$out"; then
    report "fail-depth-$depth ($rel 의 깨진 링크 탐지)" 0
  else
    report "fail-depth-$depth ($rel 의 깨진 링크 탐지)" 1 "기대 exit=1 + 경로 보고 / 실제 exit=$status: $out"
  fi
done

# 3b. 새 경계 바깥(깊이 6)은 여전히 스캔하지 않는다. 그 아래엔 우리가 심는 링크가 없고
#     깊이를 더 늘리면 비용만 는다(실측 prune 적용: depth 5 는 0.29초, depth 6 은 0.33초).
DEEP_HOME="$TMP/ok-beyond-new-depth"
mkdir -p "$DEEP_HOME/a/b/c/d/e"
ln -s "$DEEP_HOME/a/b/c/d/e/does-not-exist" "$DEEP_HOME/a/b/c/d/e/broken-link"

status=0
out=$(HOME="$DEEP_HOME" bash "$DETECTOR" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-beyond-new-depth (깊이 6은 스캔하지 않음)" 0
else
  report "ok-beyond-new-depth (깊이 6은 스캔하지 않음)" 1 "기대 exit=0 / 실제 exit=$status: $out"
fi

# 3c. 무거운 트리는 쳐낸다. 남의 저장소나 캐시 안의 깨진 링크를 보고해 봐야 조치할 것이
#     없고, 스캔 비용만 든다.
PRUNE_HOME="$TMP/ok-pruned"
mkdir -p "$PRUNE_HOME/proj/.git/refs" "$PRUNE_HOME/proj/node_modules/pkg"
ln -s "$PRUNE_HOME/proj/.git/refs/gone" "$PRUNE_HOME/proj/.git/refs/broken-link"
ln -s "$PRUNE_HOME/proj/node_modules/pkg/gone" "$PRUNE_HOME/proj/node_modules/pkg/broken-link"

status=0
out=$(HOME="$PRUNE_HOME" bash "$DETECTOR" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-pruned (.git/node_modules 내부는 무시)" 0
else
  report "ok-pruned (.git/node_modules 내부는 무시)" 1 "기대 exit=0 / 실제 exit=$status: $out"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
