#!/usr/bin/env bash
# check-agent-collision.sh
# 에이전트 실행 스크립트 이름 충돌(Collision) 검사 유틸리티

set -euo pipefail

PLAYBOOK_DIR="${1:-$HOME/dotfiles/ansible}"

# 점으로 시작하는 컨텍스트 디렉토리(.archive, .shared)는 대상에서 뺀다. 이 검사는
# "ansible ai_agent 롤이 ~/.local/bin 에 링크할 스크립트들"의 이름 충돌을 보는 것인데,
# 그 롤이 아카이브된 스킬의 스크립트를 링크하지 않으므로 여기서도 세면 안 된다.
# 세면 폐기된 스킬의 파일명이 새 스크립트 이름을 영구히 점유해, 실재하지 않는 충돌로
# `just setup` 이 막힌다.
{
  find "$PLAYBOOK_DIR/../contexts" -type f -path "*/scripts/*.sh" ! -path "*/contexts/.*" 2>/dev/null
  find "$PLAYBOOK_DIR/../bin" -type f -name "*.sh" 2>/dev/null
} | awk -F/ '
{
    name = $NF
    if (seen[name] != "") {
        print "❌ [FATAL] 스크립트 이름 충돌 감지! " name " 파일이 여러 곳에 존재합니다:" > "/dev/stderr"
        print "   1. " seen[name] > "/dev/stderr"
        print "   2. " $0 > "/dev/stderr"
        err = 1
    }
    seen[name] = $0
}
END { exit err+0 }
'
