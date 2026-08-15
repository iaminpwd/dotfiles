#!/usr/bin/env bash
# k8s-check.sh - Kubernetes-Specific Validation Pipeline
# pre-flight-check.sh가 이미 다루는 범용 검증(helm lint, kube-linter/kubectl dry-run,
# conftest, trivy fs misconfig - Kubernetes 매니페스트의 privileged/루트 실행 등
# 보안 설정 오류까지 포함)은 여기서 반복하지 않는다. 이 스크립트는 그 파이프라인이
# 다루지 못하는 K8s 전용 검증(Kyverno 네이티브 정책 테스트, PrometheusRule 문법,
# 삭제 예정 API 탐지)만 담당한다.

set -euo pipefail

# 이 스크립트는 contexts/<skill>/scripts/preflight/ 배치 규약으로만 존재하며 그 규약의
# 주인이 pre-flight-check 스킬이므로, 라이브러리도 같은 곳에서 가져온다. scripts/ 디렉토리는
# ~/.claude/skills/k8s/scripts 로 심볼릭 링크되어 배포되므로 BASH_SOURCE 를 그대로 쓰면
# 상대 경로가 배포 위치로 빗나간다. readlink -f 로 저장소 내 정본 위치를 먼저 확정한다.
K8S_CHECK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$K8S_CHECK_DIR/../../lib/script-init.sh"
# 검사 대상 수집 SSOT. pre-flight-check.sh 가 넘긴 대상 목록이 있으면 그걸 쓰고,
# 인자 없이 직접 호출되면(회귀 테스트·수동 실행) 스테이징 기준으로 폴백한다.
# shellcheck source-path=SCRIPTDIR
source "$K8S_CHECK_DIR/../../lib/plugin-targets.sh"
PLUGIN_TARGET_FILES=("$@")

log_info "======================================================"
log_info "=== K8s-Specific Validation Pipeline Started ==="
log_info "======================================================"

init_repo_root

# 도구 가용성 조회는 pre-flight-check 스킬의 공용 라이브러리를 source 한다. 이게 없으면
# promtool/pluto 부재 시 문법이 깨진 PrometheusRule을 검사하지 않고도 "Passed
# Successfully"를 출력하는 무검증 통과가 생긴다.
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
  mapfile -d '' -t test_files < <(plugin_target_files '*kyverno-test.yaml')
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

  # 문서 단위로 검사한다. 예전엔 파일 전체에 `yq eval '.spec'` 을 걸었는데, 멀티 도큐먼트
  # 매니페스트(K8s 에서 아주 흔하다)에서 게이트가 통째로 무력화됐다 — PrometheusRule 이
  # 아닌 문서는 `.spec` 이 null 로 나오고, 그 null 이 출력의 첫 문서가 되면 promtool 이
  # "Multiple document yaml rules files are not supported, only the first document is
  # processed" 를 경고하며 그 null 만 보고 "0 rules found / SUCCESS" 로 끝난다.
  # 실측: 깨진 PromQL 이 단독 파일이면 exit 1 로 막히는데, 앞에 ConfigMap 문서 하나만
  # 붙이면 exit 0 으로 통과했다.
  # PrometheusRule 문서가 여러 개인 파일도 같은 이유로 첫 개만 검사됐으므로, 문서마다
  # 따로 뽑아 promtool 에 넘긴다.
  local f last_idx idx kind tmp
  for f in "${rule_files[@]}"; do
    log_info "Checking PrometheusRule: $f"
    last_idx=$(yq eval 'documentIndex' "$f" 2>/dev/null | tail -1)
    if ! [[ "$last_idx" =~ ^[0-9]+$ ]]; then
      echo "❌ [ERROR] PrometheusRule 문서 구조를 읽지 못했습니다: $f" >&2
      return 1
    fi
    for ((idx = 0; idx <= last_idx; idx++)); do
      kind=$(yq eval "select(documentIndex == $idx) | .kind" "$f" 2>/dev/null)
      [ "$kind" = "PrometheusRule" ] || continue
      tmp=$(mktemp)
      # promtool은 순수 groups: 포맷만 이해하므로, CRD 래퍼(apiVersion/kind/metadata)를
      # 벗기고 해당 문서의 spec 블록만 추출해 넘긴다.
      if ! yq eval "select(documentIndex == $idx) | .spec" "$f" >"$tmp"; then
        rm -f "$tmp" 2>/dev/null || true
        echo "❌ [ERROR] PrometheusRule의 .spec 블록 추출에 실패했습니다: $f (문서 $idx)" >&2
        return 1
      fi
      if ! promtool check rules "$tmp"; then
        rm -f "$tmp" 2>/dev/null || true
        echo "❌ [ERROR] PromQL Alerting Rule 문법 검증에 실패하여 커밋이 중단되었습니다: $f (문서 $idx)" >&2
        return 1
      fi
      rm -f "$tmp" 2>/dev/null || true
    done
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
  # 스테이징된 매니페스트만 격리된 임시 디렉토리에 복사해 스캔 범위를 좁힌다(무관한
  # 매니페스트가 저장소 어딘가에 있으면 -d . 이 그것까지 잡아 무관한 커밋을 차단한다).
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
  mapfile -d '' -t GLOBAL_STAGED_YAML_FILES < <(plugin_target_files '*.yaml' '*.yml')

  check_kyverno
  check_prometheus_rules
  check_deprecated_apis

  log_info "======================================================"
  log_info "=== K8s-Specific Checks Passed Successfully ==="
  # tool-probe.sh 로드는 위에서 조건부라, 못 찾은 환경(구버전 배포본 등)에서 무가드로
  # 호출하면 set -e 가 여기서 스크립트를 죽여 "검증 실패"로 오보고된다.
  # aiops-check.sh 와 동일하게 존재 확인 후 호출한다.
  if declare -F print_unavailable_tools >/dev/null; then
    print_unavailable_tools
  fi
  log_info "======================================================"
}

main
