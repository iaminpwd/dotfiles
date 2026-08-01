#!/usr/bin/env bash
# tool-probe.sh - 검증 도구 가용성 조회 공용 라이브러리 (SSOT)
# pre-flight-check.sh 및 플러그인 검증기 공용 도구 탐색 라이브러리입니다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source "$LIB_PATH/tool-probe.sh"
#   has_tool shellcheck || echo "미설치"
#   print_unavailable_tools   # 실행 후 미가용 도구 요약 배너 출력

# 검증을 수행하지 못한 도구 목록 추적
UNAVAILABLE_TOOLS=()

record_unavailable() {
  local t existing
  t=$1
  for existing in "${UNAVAILABLE_TOOLS[@]:-}"; do
    [ "$existing" = "$t" ] && return 0
  done
  UNAVAILABLE_TOOLS+=("$t")
}

has_tool() {
  local resolved
  resolved=$(command -v "$1") || {
    record_unavailable "$1"
    return 1
  }

  # mise shim 검증: PATH에 존재하더라도 현재 디렉토리 세션에서 해석 가능한지 점검
  if [[ "$resolved" == "$HOME/.local/share/mise/shims/"* ]] && command -v mise &>/dev/null; then
    if ! mise which "$1" &>/dev/null; then
      local real
      real=$(find "$HOME/.local/share/mise/installs/$1" -maxdepth 3 -name "$1" -type f -perm -u+x 2>/dev/null | sort -V | tail -1)
      if [ -n "$real" ] && "$real" --version &>/dev/null; then
        PATH="$(dirname "$real"):$PATH"
        export PATH
        return 0
      fi
      record_unavailable "$1"
      return 1
    fi
  fi
}

# 검증 수행 불가능 도구가 있을 경우 요약 경고 배너 출력
print_unavailable_tools() {
  [ "${#UNAVAILABLE_TOOLS[@]}" -gt 0 ] || return 0
  echo "=== ⚠️  단, 아래 도구를 사용할 수 없어 해당 검증은 수행되지 않았습니다:"
  echo "===    ${UNAVAILABLE_TOOLS[*]}"
  echo "===    (미설치라면 'mise install -y', 설치했는데도 뜨면 ~/.config/mise/config.toml 존재 여부를 확인하십시오)"
}
