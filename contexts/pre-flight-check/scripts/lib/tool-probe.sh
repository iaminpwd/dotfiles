#!/usr/bin/env bash
# tool-probe.sh - 검증 도구 가용성 조회 공용 라이브러리 (SSOT)
#
# pre-flight-check.sh 와 각 스킬의 scripts/preflight/*.sh 위임 검증기가 공유한다.
# 예전에는 이 34줄이 두 파일에 복제돼 있었고, 주석만 다르고 실행 로직은 100% 동일했다
# (2026-07-28 실측). 한쪽만 고치면 다른 쪽이 조용히 옛 동작을 유지하는데, 하필 이 로직의
# 실패 모드가 "모든 검증을 건너뛰고 성공 배너를 출력하는 것"이라 드리프트를 눈으로
# 알아챌 수 없다. 위임 스킬이 늘 때마다 사본이 하나씩 늘어나는 구조이기도 하다.
#
# source 전용이므로 set -euo pipefail 을 선언하지 않는다. 호출자의 셸 옵션을 덮어쓰면
# 라이브러리가 호출자의 에러 처리 정책을 바꾸게 된다(tests/lib/tf-fixture-lib.sh 와 동일).
#
# 사용:
#   LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/tool-probe.sh"
#   source "$LIB"
#   has_tool shellcheck || echo "없음"
#   print_unavailable_tools   # 마지막 요약 배너 안에서 호출

# 실제로 검증을 수행하지 못한 도구 목록. 마지막 요약에서 함께 출력해, 아무것도 검사하지
# 않고 "Checks Passed"만 보이는 상황(가짜 초록불)을 사용자가 알아챌 수 있게 한다.
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
  # mise shim 파일은 command -v로 항상 발견되지만, 해당 도구의 버전이 현재 디렉토리에서
  # 해석되지 않으면(예: mise 설정이 미치지 못하는 위치) 실제 호출 시점에 실패한다.
  # 각 도구마다 다른 --version 플래그를 흉내내는 대신, mise 자체에 해석 가능 여부를 물어본다.
  # 단, PATH에서 찾은 경로가 mise shims 디렉토리 소속일 때만 이 재검증을 수행한다. zsh처럼
  # mise가 애초에 관리하지 않는 시스템 도구(apt 설치)까지 무조건 "mise which"로 되물으면
  # "not a mise bin" 오류로 오탐 처리되어, 실제로는 정상 설치된 도구를 건너뛰게 된다.
  if [[ "$resolved" == "$HOME/.local/share/mise/shims/"* ]] && command -v mise &>/dev/null; then
    if ! mise which "$1" &>/dev/null; then
      # 해석 실패는 "미설치"가 아니라 "이 위치에서 shim이 동작하지 않음"이다. 설치 원본이
      # 존재하면 그 경로를 PATH 앞에 붙여 실제로 호출 가능하게 만든다. 이 폴백이 없으면
      # $HOME 밖 저장소에서 모든 검증이 "미설치"로 스킵된 채 "All Checks Passed"가 출력되어
      # 무검증 통과로 이어진다(2026-07-26 실측: /tmp 클론에서 shellcheck/shfmt 전부 스킵).
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

# 성공 배너 안에서 호출한다. 조회하지 못한 도구가 없으면 아무것도 출력하지 않으므로,
# 호출부에서 개수를 다시 검사할 필요가 없다.
print_unavailable_tools() {
  [ "${#UNAVAILABLE_TOOLS[@]}" -gt 0 ] || return 0
  echo "=== ⚠️  단, 아래 도구를 사용할 수 없어 해당 검증은 수행되지 않았습니다:"
  echo "===    ${UNAVAILABLE_TOOLS[*]}"
  echo "===    (미설치라면 'mise install -y', 설치했는데도 뜨면 mise 전역 설정"
  echo "===     ~/.config/mise/config.toml 존재 여부를 확인하십시오)"
}
