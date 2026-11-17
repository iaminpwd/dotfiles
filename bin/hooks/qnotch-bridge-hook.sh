#!/usr/bin/env bash
# qnotch-bridge-hook.sh - WSL의 Claude Code 훅 이벤트를 Windows QNotch로 전달하는 훅 래퍼.
#
# QNotch(Windows 노치 앱)는 Windows 쪽 Claude 설정에만 훅을 등록하므로 WSL에서 도는
# Claude Code 세션이 보이지 않는다. 실제 전달과 서브에이전트 상태 보정은 같은
# 디렉터리의 bin/hooks/qnotch-bridge.py 가 한다. WSL이 아니면 아무것도 하지 않는다.
# merge-agent-hooks.sh 가 WSL에서만 이 훅을 등록한다.
#
# -e(errexit) 는 의도적으로 제외: 훅 실패가 에이전트 루프를 멈추지 않도록 항상 0으로
# 끝내고, 표준 출력은 비워 둔다(Stop 등에서 출력이 결정으로 해석되지 않게).
set -uo pipefail

# GNU readlink -f는 macOS 기본 BSD readlink에 없으므로 plain readlink + cd -P만으로
# 자기 symlink 체인을 해석한다.
canonical_path() {
  local path=$1 dir target
  while [ -L "$path" ]; do
    dir=$(cd -P "$(dirname "$path")" && pwd) || return 1
    target=$(readlink "$path") || return 1
    case "$target" in
    /*) path="$target" ;;
    *) path="$dir/$target" ;;
    esac
  done
  dir=$(cd -P "$(dirname "$path")" && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

# 테스트는 DOTFILES_FORCE_WSL=0/1 로 판정을 고정한다(merge-agent-hooks.sh 와 같은 규칙).
is_wsl() {
  case "${DOTFILES_FORCE_WSL:-}" in
  1) return 0 ;;
  0) return 1 ;;
  esac
  grep -qi microsoft /proc/version 2>/dev/null
}

is_wsl || exit 0

QBH_SCRIPT_PATH=$(canonical_path "${BASH_SOURCE[0]}" 2>/dev/null) || exit 0
QBH_PYTHON=/usr/bin/python3
[ -x "$QBH_PYTHON" ] || QBH_PYTHON=$(command -v python3 2>/dev/null) || exit 0

# stdin(훅 JSON)은 그대로 넘긴다. -I 로 사용자 site-packages·PYTHON* 환경을 무시한다.
"$QBH_PYTHON" -I "$(dirname "$QBH_SCRIPT_PATH")/qnotch-bridge.py" >/dev/null 2>&1
exit 0
