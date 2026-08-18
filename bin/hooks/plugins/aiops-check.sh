#!/usr/bin/env bash
# aiops-check.sh - AIOps Telemetry Manifest Validation Pipeline
#
# contexts/aiops/scripts/validate-telemetry-schema.sh(평문 시크릿 검사 + ISMS-P
# ClosedLoopPolicy 가드레일)를 bin/hooks/plugins/*.sh 자동 로드 경로에 배선한다
# (k8s-check.sh/observability-check.sh와 동일한 패턴).
#
# 이 훅은 전역 core.hooksPath로 dotfiles 밖 임의 저장소에서도 실행되므로, contexts/
# 경로가 아니라 CRD kind: 시그니처로 "텔레메트리 매니페스트인지"를 판정한다
# (k8s-check.sh의 PrometheusRule kind: 판정과 동일 이유).
#
# validate-telemetry-schema.sh는 파일 목록이 아니라 디렉토리를 재귀 스캔하는
# 인터페이스라(TARGET_DIR), 트리거된 경우 스테이징된 관련 파일만 격리 tmpdir에
# 모아 넘긴다(무관한 저장소 전체를 훑으면 무관한 커밋까지 차단하기 때문).

set -euo pipefail

# 이 스크립트는 contexts/<skill>/scripts/preflight/ 배치 규약으로만 존재하며 그 규약의
# 주인이 pre-flight-check 스킬이므로, 라이브러리도 같은 곳에서 가져온다(k8s-check.sh와 동일 이유).
AIOPS_CHECK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$AIOPS_CHECK_DIR/../../lib/script-init.sh"
# 검사 대상 수집 SSOT (k8s-check.sh 와 동일 이유 — bin/lib/plugin-targets.sh 헤더 참조).
# shellcheck source-path=SCRIPTDIR
source "$AIOPS_CHECK_DIR/../../lib/plugin-targets.sh"
PLUGIN_TARGET_FILES=("$@")
# 나머지 두 플러그인과 동일하게 도구 가용성 요약 배너를 남기기 위해 tool-probe.sh 를 로드한다.
# 이 플러그인은 has_tool 을 직접 쓰지 않지만, 위임 대상인 validate-telemetry-schema.sh 가
# 도구 부재로 검증을 건너뛰었을 때 print_unavailable_tools 가 그 사실을 드러낼 수 있어야 한다.
# shellcheck source-path=SCRIPTDIR
if [ -f "$AIOPS_CHECK_DIR/../../lib/tool-probe.sh" ]; then
  source "$AIOPS_CHECK_DIR/../../lib/tool-probe.sh"
fi

log_info "======================================================"
log_info "=== AIOps-Specific Validation Pipeline Started ==="
log_info "======================================================"

init_repo_root

VALIDATOR="$AIOPS_CHECK_DIR/../../../contexts/aiops/scripts/validate-telemetry-schema.sh"
if [ ! -f "$VALIDATOR" ]; then
  VALIDATOR="$REPO_ROOT/contexts/aiops/scripts/validate-telemetry-schema.sh"
fi

GLOBAL_IS_GIT_REPO=0
if git rev-parse --is-inside-work-tree &>/dev/null; then
  GLOBAL_IS_GIT_REPO=1
fi

# 텔레메트리 매니페스트(시크릿/ISMS-P 가드레일) 검증
check_telemetry_manifests() {
  local staged=() manifest_files=() scan_files=() f
  mapfile -d '' -t staged < <(plugin_target_files '*.yaml' '*.yml' '*.json' '*.tf')
  [ "${#staged[@]}" -eq 0 ] && return 0

  # 판정 트리거: yaml/yml 중 ClosedLoopPolicy/TelemetryCollectorConfig kind가 하나라도
  # 스테이징돼야 활성화한다(무관한 저장소의 모든 yaml/tf/json 커밋마다 도는 것을 방지).
  for f in "${staged[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$f" in
    *.yaml | *.yml)
      grep -qE "^kind:[[:space:]]*(ClosedLoopPolicy|TelemetryCollectorConfig)" "$f" 2>/dev/null && manifest_files+=("$f")
      ;;
    esac
  done
  [ "${#manifest_files[@]}" -eq 0 ] && return 0

  if [ ! -f "$VALIDATOR" ]; then
    log_info "--- Step: AIOps Telemetry Manifest Validation ---"
    log_info "[WARNING] validate-telemetry-schema.sh 를 찾을 수 없어 검증을 건너뜁니다."
    return 0
  fi

  log_info "--- Step: AIOps Telemetry Manifest Validation ---"

  # 위임 대상(validate-telemetry-schema.sh)은 yamllint 가 없으면 YAML 문법 검사 블록을
  # 통째로 건너뛰는데, 그 사실은 아무 데도 남지 않는다. 게다가 그쪽은 별도 프로세스라
  # UNAVAILABLE_TOOLS 가 이 프로세스로 전파될 수도 없어서, 아래 main() 의
  # print_unavailable_tools 는 지금까지 어떤 경우에도 한 줄도 출력할 수 없었다(이 파일
  # 상단 주석이 선언한 목적이 구조적으로 달성 불가능한 상태였다 — 발동하지 않는 안전장치는
  # 없는 것과 같다). 여기서 같은 도구의 가용성을 직접 판정해 요약 배너에 싣는다.
  # 판정만 하고 진행 여부는 바꾸지 않는다: 평문 시크릿 검사(하드 블록)는 grep 만 쓰므로
  # yamllint 부재로 건너뛰어서는 안 된다.
  if declare -F has_tool >/dev/null && ! has_tool yamllint; then
    log_info "[WARNING] yamllint 이 없어 위임 검증의 YAML 문법 검사는 수행되지 않습니다."
  fi

  # 트리거된 경우, 같은 커밋에 함께 스테이징된 yaml/yml/json/tf 전체를 대상으로 삼는다
  # (시크릿이 kind: 매니페스트가 아니라 옆에 딸린 .tf/.json에 있을 수도 있으므로).
  for f in "${staged[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    scan_files+=("$f")
  done

  local tmpdir i=0
  tmpdir=$(mktemp -d)
  for f in "${scan_files[@]}"; do
    mkdir -p "$tmpdir/$((i))"
    cp "$f" "$tmpdir/$((i++))/$(basename "$f")"
  done

  if ! bash "$VALIDATOR" "$tmpdir"; then
    rm -rf "$tmpdir"
    echo "❌ [ERROR] AIOps 텔레메트리 매니페스트 검증(시크릿/가드레일)에 실패하여 커밋이 중단되었습니다." >&2
    printf '    %s\n' "${manifest_files[@]}" >&2
    return 1
  fi
  rm -rf "$tmpdir"
  log_info "[SUCCESS] AIOps telemetry manifest validation passed."
}

main() {
  check_telemetry_manifests

  log_info "======================================================"
  log_info "=== AIOps-Specific Checks Passed Successfully ==="
  # tool-probe.sh 를 로드하지 못한 환경(구버전 배포본 등)에서도 죽지 않도록 존재 확인 후 호출.
  if declare -F print_unavailable_tools >/dev/null; then
    print_unavailable_tools
  fi
  log_info "======================================================"
}

main
