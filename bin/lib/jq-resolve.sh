#!/usr/bin/env bash
# jq-resolve.sh - PATH의 jq(mise shim)가 실행 불가능할 때 mise 설치 디렉토리에서 실제
# 바이너리를 직접 찾아내는 공용 라이브러리 (SSOT).
# mise shim은 $HOME 기준으로 설치 위치를 찾기 때문에, $HOME을 격리 디렉토리로 덮어써서
# 테스트/실행하는 환경(예: 픽스처 테스트)에서는 shim이 조용히 jq를 못 찾는 경우가 있다
# (실측: test-merge-agent-hooks.sh 작성 중 발견). agent-edits-hook.sh(자동 훅)와
# merge-agent-hooks.sh(ansible 호출)가 이 폴백 로직을 그대로 복제하고 있던 것을 뽑아냈다.
# 해석 실패 시 처리(조용히 exit할지, 그냥 진행할지)는 스크립트마다 의도적으로 다르므로
# 호출부에 그대로 남겨둔다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source "$LIB_PATH/jq-resolve.sh"
#   JQ=$(resolve_jq)

# resolve_jq
# stdout: 실행 가능한 jq 경로 (PATH 우선, 실패 시 mise 설치 디렉토리 최신 버전으로 폴백. 둘 다 없으면 빈 문자열)
resolve_jq() {
  local jq_bin
  jq_bin=$(command -v jq 2>/dev/null) || jq_bin=""
  if [ -z "$jq_bin" ] || ! "$jq_bin" --version >/dev/null 2>&1; then
    jq_bin=$(find "$HOME/.local/share/mise/installs/jq" -maxdepth 3 -name jq -type f 2>/dev/null | sort -V | tail -1)
  fi
  printf '%s' "$jq_bin"
}
