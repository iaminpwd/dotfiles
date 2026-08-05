#!/usr/bin/env bash
# script-init.sh - 저장소 루트 판정 + 루트로 cd + QUIET 모드 로깅 헬퍼 공용 라이브러리 (SSOT)
# pre-flight-check.sh, prompt-lint.sh, test-coverage-check.sh, k8s-check.sh,
# observability-check.sh, aiops-check.sh, run-suite.sh 일곱 곳에 그대로 복붙돼 있던
# 초기화 보일러플레이트를 뽑아냈다.
#
# [주의] generate-context-index.sh는 의도적으로 이 라이브러리를 쓰지 않는다. 이 스크립트의
# init_repo_root()는 "호출 시점 CWD의 현재 저장소"를 찾는 범용 로직인데,
# generate-context-index.sh는 항상 자기 자신이 속한 dotfiles 저장소만 다루는 전용
# 도구라 CWD와 무관해야 하기 때문이다(자세한 사유는 그 스크립트 자신의 주석 참고).
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source "$LIB_PATH/script-init.sh"
#   log_info "..."   # QUIET=1(기본, AI 토큰 절약)이면 억제, QUIET=0이면 출력
#   init_repo_root    # REPO_ROOT 전역 변수를 설정하고 그 경로로 cd (실패 시 exit 1)

log_info() {
  # Default to QUIET=1 for AI token savings, unless explicitly set to 0
  if [ "${QUIET:-1}" != "1" ]; then
    echo "$@"
  fi
}

init_repo_root() {
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  cd "$REPO_ROOT" || {
    echo "[ERROR] 저장소 루트($REPO_ROOT)로 이동할 수 없습니다." >&2
    exit 1
  }
}
