#!/usr/bin/env bash
# ai_agent role이 과거에 ~/.local/bin에 배포했지만 현재 저장소에서 삭제된 스크립트 링크 정리.
# 깨진 링크 중 target이 이 dotfiles 저장소의 bin/ 또는 contexts/ 하위일 때만 소유 링크로 본다.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <repo-root> <local-bin>" >&2
  exit 2
fi

REPO_ROOT=$(cd "$1" && pwd -P)
LOCAL_BIN=$2

[ -d "$LOCAL_BIN" ] || exit 0

for link in "$LOCAL_BIN"/*; do
  [ -L "$link" ] || continue
  [ -e "$link" ] && continue

  target=$(readlink "$link" 2>/dev/null || true)
  case "$target" in
  "$REPO_ROOT"/bin/* | "$REPO_ROOT"/contexts/*)
    rm -f "$link"
    echo "[PRUNED] $link"
    ;;
  *)
    # 공유 ~/.local/bin에는 사용자가 만든 링크도 있으므로 소유권이 확인되지 않으면 보존한다.
    echo "[SKIP] foreign broken symlink: $link"
    ;;
  esac
done
