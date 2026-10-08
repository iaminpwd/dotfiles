#!/usr/bin/env bash
# 과거 ai_agent role이 ~/.local/bin에 평탄화한 dotfiles 소유 스크립트 링크를 회수한다.
# ~/.local/bin은 공유 경로이므로 이 저장소의 bin/ 또는 contexts/를 절대경로로 가리키는
# 심볼릭 링크만 제거하고 외부 사용자 링크는 살아 있든 깨졌든 보존한다.
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

  target=$(readlink "$link" 2>/dev/null || true)
  # 이전 ai_agent 롤은 실행 파일만 `bin/` 또는 `contexts/*/scripts/`에서
  # 찾아 목적지에 원본의 basename 그대로 절대경로로 연결했다.
  # 같은 저장소를 가리켜도 사용자가 만든 별칭이나 SKILL.md 링크는 소유하지 않는다.
  case "$target" in
  "$REPO_ROOT"/bin/* | "$REPO_ROOT"/contexts/*/scripts/*)
    # ../ 또는 ./ 경유는 원본 롤이 생성하지 않았으므로 정리 권한을 추정하지 않는다.
    case "$target" in
    */../* | */./*) echo "[SKIP] foreign symlink: $link"; continue ;;
    esac
    [ "${target##*/}" = "${link##*/}" ] || {
      echo "[SKIP] foreign symlink: $link"
      continue
    }
    rm -f "$link"
    echo "[PRUNED] $link"
    ;;
  *)
    # 과거 롤이 만든 링크는 절대경로 src였으므로, 그 외 형식은 소유권을 확정할 수 없다.
    echo "[SKIP] foreign symlink: $link"
    ;;
  esac
done
