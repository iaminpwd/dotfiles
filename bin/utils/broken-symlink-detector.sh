#!/usr/bin/env bash
# broken-symlink-detector.sh
# 홈 디렉토리 내의 깨진 심볼릭 링크(고아 링크) 탐지

set -euo pipefail

# 이 저장소가 실제로 링크를 심는 깊이까지 훑는다. 예전엔 -maxdepth 2 였는데, 그러면
# ansible ai_agent 롤이 거는 링크가 하나도 사정권에 들지 않았다(실측한 현재 배치):
#   ~/.local/bin/<script>.sh                     깊이 3
#   ~/.claude/skills/<skill>/SKILL.md            깊이 4
#   ~/.gemini/config/skills/<skill>/<file>       깊이 5   <- 가장 깊다
# 실측: 폐기 스킬을 지운 뒤 ~/.local/bin 에 남아 있던 깨진 링크 3개를 이 탐지기가
# "0건"으로 보고했다 — 존재 이유인 바로 그 경로를 못 보고 있었다.
#
# 그래서 경계를 5로 잡는다(prune 적용 시 0.29초, 2일 때 0.04초). 6으로 더 늘려도
# 0.33초로 큰 차이는 없지만 그 아래에 우리가 심는 링크가 없어 이득이 없다.
# 무거운 트리는 미리 쳐낸다 — 안에 우리가 만든 링크가 없고, 남의 저장소나 캐시의
# 깨진 링크를 보고해 봐야 사용자가 조치할 것이 없다.
BROKEN_LINKS=$(find "$HOME" -maxdepth 5 \
  \( -name .git -o -name node_modules -o -name .cache -o -name installs -o -name .venv \) -prune -o \
  -type l ! -exec test -e {} \; -print 2>/dev/null || true)

if [ -n "$BROKEN_LINKS" ]; then
  echo "[ERROR] 깨진 심볼릭 링크(고아 링크)가 발견되었습니다:"
  echo "$BROKEN_LINKS"
  exit 1
fi

exit 0
