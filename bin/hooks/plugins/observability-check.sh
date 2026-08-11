#!/usr/bin/env bash
# observability-check.sh - Observability-Specific Validation Pipeline
# pre-flight-check.sh(범용 yamllint)와 k8s-check.sh(PrometheusRule PromQL 문법,
# promtool)가 이미 다루는 영역은 여기서 반복하지 않는다. 이 스크립트는 그 파이프라인이
# 다루지 못하는 020-metrics-alerting-standard.md §4 의 의미론적 정책(Critical 알람
# runbook_url 필수, 고카디널리티 레이블 금지)만 담당한다.

set -euo pipefail

# scripts/ 디렉토리는 ~/.claude/skills/observability/scripts 로 심볼릭 링크되어 배포되므로
# BASH_SOURCE 를 그대로 쓰면 상대 경로가 배포 위치로 빗나간다(k8s-check.sh 와 동일 이유).
OBS_CHECK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$OBS_CHECK_DIR/../../lib/script-init.sh"
# 검사 대상 수집 SSOT (k8s-check.sh 와 동일 이유 — bin/lib/plugin-targets.sh 헤더 참조).
# shellcheck source-path=SCRIPTDIR
source "$OBS_CHECK_DIR/../../lib/plugin-targets.sh"
PLUGIN_TARGET_FILES=("$@")

log_info "======================================================"
log_info "=== Observability-Specific Validation Pipeline Started ==="
log_info "======================================================"

init_repo_root

# 도구 가용성 조회는 pre-flight-check 스킬의 공용 라이브러리를 source 한다.
# shellcheck source-path=SCRIPTDIR
if [ -f "$OBS_CHECK_DIR/../../lib/tool-probe.sh" ]; then
  source "$OBS_CHECK_DIR/../../lib/tool-probe.sh"
elif [ -f "$REPO_ROOT/bin/lib/tool-probe.sh" ]; then
  source "$REPO_ROOT/bin/lib/tool-probe.sh"
fi

# 검증기 본체(validate-alert-rules.sh)도 같은 이유로 배포 위치가 아닌 정본 위치를
# readlink -f 로 먼저 확정한 뒤 상대 경로로 접근한다.
VALIDATOR="$OBS_CHECK_DIR/../../../contexts/observability/scripts/validate-alert-rules.sh"
if [ ! -f "$VALIDATOR" ]; then
  VALIDATOR="$REPO_ROOT/contexts/observability/scripts/validate-alert-rules.sh"
fi

GLOBAL_IS_GIT_REPO=0
if git rev-parse --is-inside-work-tree &>/dev/null; then
  GLOBAL_IS_GIT_REPO=1
fi

# Prometheus Alerting Rule 정책 검증 (PrometheusRule CRD)
check_alert_rule_policy() {
  local staged_yaml=() rule_files=() f
  mapfile -d '' -t staged_yaml < <(plugin_target_files '*.yaml' '*.yml')
  for f in "${staged_yaml[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    grep -qE "^kind:[[:space:]]*PrometheusRule" "$f" 2>/dev/null && rule_files+=("$f")
  done
  if [ "${#rule_files[@]}" -eq 0 ]; then
    return 0
  fi

  log_info "--- Step: Observability Alerting Rule Policy Validation ---"
  if [ ! -f "$VALIDATOR" ]; then
    log_info "[WARNING] validate-alert-rules.sh 를 찾을 수 없어 정책 검증을 건너뜁니다."
    return 0
  fi
  if ! has_tool yq; then
    log_info "[WARNING] PrometheusRule manifest found but 'yq' is not installed. Skipping policy validation."
    return 0
  fi

  for f in "${rule_files[@]}"; do
    log_info "Checking alerting rule policy: $f"
    if ! bash "$VALIDATOR" "$f"; then
      echo "❌ [ERROR] 알람 정책(020-metrics-alerting-standard.md §4) 위반이 감지되어 커밋이 중단되었습니다: $f" >&2
      return 1
    fi
  done
  log_info "[SUCCESS] Observability alerting rule policy validation passed."
}

main() {
  check_alert_rule_policy

  log_info "======================================================"
  log_info "=== Observability-Specific Checks Passed Successfully ==="
  print_unavailable_tools
  log_info "======================================================"
}

main
