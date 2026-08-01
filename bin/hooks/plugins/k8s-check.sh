#!/usr/bin/env bash
# k8s-check.sh - Kubernetes-Specific Validation Pipeline
# pre-flight-check.sh가 이미 다루는 범용 검증(helm lint, kube-linter/kubectl dry-run,
# conftest, trivy fs misconfig - Kubernetes 매니페스트의 privileged/루트 실행 등
# 보안 설정 오류까지 포함)은 여기서 반복하지 않는다. 이 스크립트는 그 파이프라인이
# 다루지 못하는 K8s 전용 검증(Kyverno 네이티브 정책 테스트, PrometheusRule 문법,
# 삭제 예정 API 탐지)만 담당한다.

set -euo pipefail

# Setup Quiet Mode Logging
log_info() {
  # Default to QUIET=1 for AI token savings, unless explicitly set to 0
  if [ "${QUIET:-1}" != "1" ]; then
    echo "$@"
  fi
}

log_info "======================================================"
log_info "=== K8s-Specific Validation Pipeline Started ==="
log_info "======================================================"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT" || {
  echo "[ERROR] 저장소 루트($REPO_ROOT)로 이동할 수 없습니다." >&2
  exit 1
}

# 도구 가용성 조회는 pre-flight-check 스킬의 공용 라이브러리를 source 한다. 이 장치가
# 이 스크립트에 없던 시절에는 promtool/pluto 부재 시 문법이 깨진 PrometheusRule을 한 번도
# 검사하지 않고 "Passed Successfully"를 출력했다(2026-07-27 실측: PATH에서 도구를 제거하면
# exit 0 + 성공 배너).
#
# 이 스크립트는 contexts/<skill>/scripts/preflight/ 배치 규약으로만 존재하며 그 규약의
# 주인이 pre-flight-check 스킬이므로, 라이브러리도 같은 곳에서 가져온다. scripts/ 디렉토리는
# ~/.claude/skills/k8s/scripts 로 심볼릭 링크되어 배포되므로 BASH_SOURCE 를 그대로 쓰면
# 상대 경로가 배포 위치로 빗나간다. readlink -f 로 저장소 내 정본 위치를 먼저 확정한다.
K8S_CHECK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
if [ -f "$K8S_CHECK_DIR/../../lib/tool-probe.sh" ]; then
  source "$K8S_CHECK_DIR/../../lib/tool-probe.sh"
elif [ -f "$REPO_ROOT/bin/lib/tool-probe.sh" ]; then
  source "$REPO_ROOT/bin/lib/tool-probe.sh"
fi

GLOBAL_IS_GIT_REPO=0
if git rev-parse --is-inside-work-tree &>/dev/null; then
  GLOBAL_IS_GIT_REPO=1
fi

# main()에서 1회만 조회하여 각 check 함수가 재사용 (git diff 반복 호출 최소화)
GLOBAL_STAGED_YAML_FILES=()

# -----------------------------------------------------------------------------
# Validation Sub-modules (Isolated Functions)
# -----------------------------------------------------------------------------

# 1. Kyverno Native Policy Test
check_kyverno() {
  local test_files=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t test_files < <(git diff --cached --name-only -z --diff-filter=ACM -- '*kyverno-test.yaml' 2>/dev/null)
  fi
  if [ "${#test_files[@]}" -eq 0 ] || [ -z "${test_files[0]}" ]; then
    return 0
  fi

  log_info "--- Step: Kyverno Policy Test ---"
  if ! has_tool kyverno; then
    log_info "[WARNING] kyverno-test.yaml found but 'kyverno' CLI is not installed. Skipping."
    return 0
  fi

  # kyverno test는 kyverno-test.yaml이 위치한 디렉토리 단위로 실행되므로, 변경된
  # 테스트 파일들이 속한 디렉토리를 중복 없이 모아 각 디렉토리마다 1회 실행한다.
  local dirs=() f d found existing
  for f in "${test_files[@]}"; do
    [ -z "$f" ] && continue
    d=$(dirname "$f")
    found=0
    for existing in "${dirs[@]:-}"; do
      [ "$existing" = "$d" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && dirs+=("$d")
  done

  for d in "${dirs[@]}"; do
    log_info "Running kyverno test: $d"
    if ! kyverno test "$d"; then
      echo "❌ [ERROR] Kyverno 정책 테스트가 실패하여 커밋이 중단되었습니다: $d" >&2
      return 1
    fi
  done
  log_info "[SUCCESS] Kyverno policy test passed."
}

# 2. Prometheus Alerting Rule Validation (PrometheusRule CRD)
check_prometheus_rules() {
  local rule_files=() f
  for f in "${GLOBAL_STAGED_YAML_FILES[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    grep -qE "^kind:[[:space:]]*PrometheusRule" "$f" 2>/dev/null && rule_files+=("$f")
  done
  if [ "${#rule_files[@]}" -eq 0 ]; then
    return 0
  fi

  log_info "--- Step: Prometheus Alerting Rule Validation ---"
  if ! has_tool promtool; then
    log_info "[WARNING] PrometheusRule manifest found but 'promtool' is not installed. Skipping."
    return 0
  fi
  if ! has_tool yq; then
    log_info "[WARNING] PrometheusRule manifest found but 'yq' is not installed (required to extract .spec from the CRD wrapper before promtool can parse it). Skipping."
    return 0
  fi

  for f in "${rule_files[@]}"; do
    log_info "Checking PrometheusRule: $f"
    local tmp
    tmp=$(mktemp)
    # promtool은 순수 groups: 포맷만 이해하므로, CRD 래퍼(apiVersion/kind/metadata)를
    # 벗기고 spec 블록만 추출해 넘긴다.
    if ! yq eval '.spec' "$f" >"$tmp"; then
      rm -f "$tmp" 2>/dev/null || true
      echo "❌ [ERROR] PrometheusRule의 .spec 블록 추출에 실패했습니다: $f" >&2
      return 1
    fi
    if ! promtool check rules "$tmp"; then
      rm -f "$tmp" 2>/dev/null || true
      echo "❌ [ERROR] PromQL Alerting Rule 문법 검증에 실패하여 커밋이 중단되었습니다: $f" >&2
      return 1
    fi
    rm -f "$tmp" 2>/dev/null || true
  done
  log_info "[SUCCESS] Prometheus rule validation passed."
}

# 3. Deprecated / Removed K8s API Detection
check_deprecated_apis() {
  # 스테이징된 yaml이 실제 K8s 매니페스트인지(kind: 존재) 먼저 걸러낸다. 이 필터는
  # 스캔을 "트리거할지"만 정할 뿐, pluto 자체의 스캔 범위(-d .)는 좁히지 못한다.
  local manifests=() f
  for f in "${GLOBAL_STAGED_YAML_FILES[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    grep -qE "^kind:" "$f" 2>/dev/null && manifests+=("$f")
  done
  if [ "${#manifests[@]}" -eq 0 ]; then
    return 0
  fi

  log_info "--- Step: Deprecated K8s API Detection ---"
  if ! has_tool pluto; then
    log_info "[WARNING] pluto is not installed. Skipping deprecated API scan."
    return 0
  fi

  # pluto detect-files는 파일 단위 인자를 받지 못하고 -d 로 디렉토리 전체만 스캔한다.
  # 스테이징된 매니페스트만 격리된 임시 디렉토리에 복사해 스캔 범위를 좁힌다
  # (checkov 스캔의 tf_exec_checkov 격리와 동일한 이유: 무관한 매니페스트가 저장소
  # 어딘가에 있으면 -d . 이 그것까지 잡아 무관한 커밋을 차단한다. 2026-08-01 실측:
  # contexts/k8s/tests/fixtures/fail-deprecated-api.yaml 이 고정 존재하는 한, kind:
  # 가 있는 yaml을 스테이징하는 모든 커밋이 이 무관한 픽스처 때문에 막혔다).
  local tmpdir i=0
  tmpdir=$(mktemp -d)
  for f in "${manifests[@]}"; do
    cp "$f" "$tmpdir/$((i++))-$(basename "$f")"
  done

  if ! pluto detect-files -d "$tmpdir"; then
    rm -rf "$tmpdir"
    echo "❌ [ERROR] 삭제 예정(Deprecated/Removed) K8s API 버전이 감지되어 커밋이 중단되었습니다." >&2
    return 1
  fi
  rm -rf "$tmpdir"
  log_info "[SUCCESS] No deprecated/removed K8s API versions detected."
}

# -----------------------------------------------------------------------------
# Main Orchestration Flow
# -----------------------------------------------------------------------------
main() {
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t GLOBAL_STAGED_YAML_FILES < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.yaml' '*.yml' 2>/dev/null)
  fi

  check_kyverno
  check_prometheus_rules
  check_deprecated_apis

  log_info "======================================================"
  log_info "=== K8s-Specific Checks Passed Successfully ==="
  print_unavailable_tools
  log_info "======================================================"
}

main
