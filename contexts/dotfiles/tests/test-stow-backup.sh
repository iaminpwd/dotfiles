#!/usr/bin/env bash
# test-stow-backup.sh
#
# stow-backup.sh는 stow가 심볼릭 링크를 걸기 전, HOME에 이미 존재하는 실제 파일을 백업으로
# 치워주는 안전장치다. "이미 stow와 동일한 상대경로 심볼릭 링크면 건드리지 않는다"는 조건이
# 깨지면, 정상적으로 연결된 기존 심볼릭 링크를 불필요하게 백업 파일로 바꿔버리거나(멱등성
# 위반), 반대로 진짜 충돌 파일을 못 옮겨 stow가 실패하게 된다.
#
# GNU Stow는 자기가 만드는 "상대경로" 심볼릭 링크만 소유로 인식하고, 절대경로 심볼릭
# 링크는 설령 같은 파일을 가리켜도 foreign으로 보고 -R을 거부한다(실측: 이전 버전
# bootstrap.sh가 절대경로로 ln -sfn 해두었던 mise/.config/mise/config.toml에서 재현).
# 그래서 "이미 심볼릭 링크인가"가 아니라 "상대경로 형식인가"가 진짜 판정 기준이다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-stow-backup.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
BACKUP="$REPO_ROOT/bin/utils/stow-backup.sh"

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

echo "=== stow-backup.sh 충돌 파일 백업 로직 회귀 테스트 ==="

# 1. fail-real-conflict: HOME에 이미 다른 내용의 실제 파일이 있으면 백업으로 치워야 한다.
CASE1="$TMP/case1"
mkdir -p "$CASE1/dotfiles/pkg" "$CASE1/home"
echo "dotfiles 버전" >"$CASE1/dotfiles/pkg/.conflictrc"
echo "홈에 이미 있던 버전" >"$CASE1/home/.conflictrc"

bash "$BACKUP" "pkg" "$CASE1/dotfiles" "$CASE1/home"

BACKUPS=("$CASE1/home"/.conflictrc.backup.*)
if [ ! -e "$CASE1/home/.conflictrc" ] && [ -f "${BACKUPS[0]}" ] && grep -qF "홈에 이미 있던 버전" "${BACKUPS[0]}"; then
  report "fail-real-conflict (실제 파일이면 백업으로 이동)" 0
else
  report "fail-real-conflict (실제 파일이면 백업으로 이동)" 1 "$(ls -la "$CASE1/home" 2>&1)"
fi

# 2. ok-already-linked: HOME의 파일이 이미 stow와 동일한 "상대경로" 심볼릭 링크로 dotfiles
#    소스를 가리키면 건드리지 않는다.
CASE2="$TMP/case2"
mkdir -p "$CASE2/dotfiles/pkg" "$CASE2/home"
echo "dotfiles 버전" >"$CASE2/dotfiles/pkg/.linkedrc"
ln -s "../dotfiles/pkg/.linkedrc" "$CASE2/home/.linkedrc"

bash "$BACKUP" "pkg" "$CASE2/dotfiles" "$CASE2/home"

if [ -L "$CASE2/home/.linkedrc" ] && [ "$(readlink "$CASE2/home/.linkedrc")" = "../dotfiles/pkg/.linkedrc" ]; then
  report "ok-already-linked (stow와 동일한 상대경로 링크면 그대로 유지)" 0
else
  report "ok-already-linked (stow와 동일한 상대경로 링크면 그대로 유지)" 1 "$(ls -la "$CASE2/home" 2>&1)"
fi

# 2b. fail-foreign-absolute-link: 같은 파일을 가리켜도 절대경로 심볼릭 링크는 GNU Stow가
#     "not owned by stow"로 보고 -R을 거부하므로, stow가 자기 형식으로 다시 만들 수 있게
#     미리 백업으로 치워야 한다.
CASE2B="$TMP/case2b"
mkdir -p "$CASE2B/dotfiles/pkg" "$CASE2B/home"
echo "dotfiles 버전" >"$CASE2B/dotfiles/pkg/.absrc"
ln -s "$CASE2B/dotfiles/pkg/.absrc" "$CASE2B/home/.absrc"

bash "$BACKUP" "pkg" "$CASE2B/dotfiles" "$CASE2B/home"

ABS_BACKUPS=("$CASE2B/home"/.absrc.backup.*)
if [ ! -e "$CASE2B/home/.absrc" ] && [ -L "${ABS_BACKUPS[0]}" ]; then
  report "fail-foreign-absolute-link (절대경로 링크는 같은 대상이어도 백업)" 0
else
  report "fail-foreign-absolute-link (절대경로 링크는 같은 대상이어도 백업)" 1 "$(ls -la "$CASE2B/home" 2>&1)"
fi

# 2c. fail-stale-relative-link: 패키지 디렉토리가 옮겨져(예: zsh/ -> stow/zsh/) 상대경로
#     링크가 끊어진 경우도, "상대경로면 무조건 stow 소유로 본다"는 예전 로직으론 놓치고
#     GNU Stow가 "not owned by stow"로 -R을 거부한다(실측: stow/ 이관 직후 재현).
CASE2C="$TMP/case2c"
mkdir -p "$CASE2C/dotfiles/pkg" "$CASE2C/home"
echo "dotfiles 버전" >"$CASE2C/dotfiles/pkg/.movedrc"
ln -s "../old-location/pkg/.movedrc" "$CASE2C/home/.movedrc"

bash "$BACKUP" "pkg" "$CASE2C/dotfiles" "$CASE2C/home"

STALE_BACKUPS=("$CASE2C/home"/.movedrc.backup.*)
if [ ! -e "$CASE2C/home/.movedrc" ] && [ -L "${STALE_BACKUPS[0]}" ]; then
  report "fail-stale-relative-link (패키지 이동으로 끊어진 상대경로 링크는 백업)" 0
else
  report "fail-stale-relative-link (패키지 이동으로 끊어진 상대경로 링크는 백업)" 1 "$(ls -la "$CASE2C/home" 2>&1)"
fi

# 2d. fail-stale-relative-dirlink: GNU Stow는 ~/.githooks처럼 대상 디렉토리가 없으면
#     통째로 심볼릭 링크한다(tree-folding). 파일 단위로만 순회하면 이 디렉토리 링크
#     자체를 만나지 못해 정리가 안 됐다(실측: git/.githooks -> stow/git/.githooks 재현).
CASE2D="$TMP/case2d"
mkdir -p "$CASE2D/dotfiles/pkg/.hooksdir" "$CASE2D/home"
echo "dotfiles 버전" >"$CASE2D/dotfiles/pkg/.hooksdir/pre-commit"
ln -s "../old-location/pkg/.hooksdir" "$CASE2D/home/.hooksdir"

bash "$BACKUP" "pkg" "$CASE2D/dotfiles" "$CASE2D/home"

DIR_BACKUPS=("$CASE2D/home"/.hooksdir.backup.*)
if [ ! -e "$CASE2D/home/.hooksdir" ] && [ -L "${DIR_BACKUPS[0]}" ]; then
  report "fail-stale-relative-dirlink (패키지 이동으로 끊어진 디렉토리 링크는 백업)" 0
else
  report "fail-stale-relative-dirlink (패키지 이동으로 끊어진 디렉토리 링크는 백업)" 1 "$(ls -la "$CASE2D/home" 2>&1)"
fi

# 3. ok-no-conflict: HOME에 해당 경로가 아예 없으면 아무 것도 하지 않고 exit 0이어야 한다.
CASE3="$TMP/case3"
mkdir -p "$CASE3/dotfiles/pkg" "$CASE3/home"
echo "dotfiles 버전" >"$CASE3/dotfiles/pkg/.newrc"

status=0
bash "$BACKUP" "pkg" "$CASE3/dotfiles" "$CASE3/home" || status=$?
if [ "$status" -eq 0 ] && [ ! -e "$CASE3/home/.newrc" ]; then
  report "ok-no-conflict (대상 없으면 무동작 + exit 0)" 0
else
  report "ok-no-conflict (대상 없으면 무동작 + exit 0)" 1 "exit=$status $(ls -la "$CASE3/home" 2>&1)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
