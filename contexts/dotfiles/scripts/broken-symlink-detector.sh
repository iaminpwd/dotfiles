#!/usr/bin/env bash
# broken-symlink-detector.sh
# 홈 디렉토리 내의 깨진 심볼릭 링크(고아 링크) 탐지

set -euo pipefail

# ~/ 디렉토리 기준 depth 2까지 깨진 링크 찾기
BROKEN_LINKS=$(find "$HOME" -maxdepth 2 -type l ! -exec test -e {} \; -print 2>/dev/null || true)

if [ -n "$BROKEN_LINKS" ]; then
  echo "[ERROR] 깨진 심볼릭 링크(고아 링크)가 발견되었습니다:"
  echo "$BROKEN_LINKS"
  exit 1
fi

exit 0
