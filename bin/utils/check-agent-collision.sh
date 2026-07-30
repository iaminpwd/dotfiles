#!/usr/bin/env bash
# check-agent-collision.sh
# 에이전트 실행 스크립트 이름 충돌(Collision) 검사 유틸리티

set -euo pipefail

PLAYBOOK_DIR="${1:-$HOME/dotfiles/ansible}"

{
  find "$PLAYBOOK_DIR/../contexts" -type f -path "*/scripts/*.sh" 2>/dev/null
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
