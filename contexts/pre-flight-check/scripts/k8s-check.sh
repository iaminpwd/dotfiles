#!/usr/bin/env bash
# k8s-check.sh - Kubernetes-Specific Validation Pipeline
# pre-flight-check.sh가 이미 다루는 범용 검증(helm lint, kube-linter/kubectl dry-run,
# conftest, trivy fs misconfig - Kubernetes 매니페스트의 privileged/루트 실행 등
# 보안 설정 오류까지 포함)은 여기서 반복하지 않는다. 이 스크립트는 그 파이프라인이
# 다루지 못하는 K8s 전용 검증(Kyverno 네이티브 정책 테스트, PrometheusRule 문법,
# 삭제 예정 API 탐지)만 담당한다.

set -euo pipefail

echo "======================================================"
echo "=== K8s-Specific Validation Pipeline Started ==="
echo "======================================================"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT" || {
  echo "[ERROR] 저장소 루트($REPO_ROOT)로 이동할 수 없습니다." >&2
  exit 1
}

has_tool() {
  local resolved
  resolved=$(command -v "$1") || return 1
  # mise shim 파일은 command -v로 항상 발견되지만, 해당 도구의 버전이 현재 디렉토리에서
  # 해석되지 않으면 실제 호출 시점에 실패한다. mise가 관리하는 shim 경로일 때만
  # 재검증하여, mise가 관리하지 않는 시스템 도구까지 잘못 걸러내지 않도록 한다.
  if [[ "$resolved" == "$HOME/.local/share/mise/shims/"* ]] && command -v mise &>/dev/null; then
    mise which "$1" &>/dev/null || return 1
  fi
}

GLOBAL_IS_GIT_REPO=0
if git rev-parse --is-inside-work-tree &>/dev/null; then
  GLOBAL_IS_GIT_REPO=1
fi

# main()에서 1회만 조회하여 각 check 함수가 재사용 (git diff 반복 호출 방지)
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

  echo "--- Step: Kyverno Policy Test ---"
  if ! has_tool kyverno; then
    echo "[WARNING] kyverno-test.yaml found but 'kyverno' CLI is not installed. Skipping."
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
    echo "Running kyverno test: $d"
    if ! kyverno test "$d"; then
      echo "❌ [ERROR] Kyverno 정책 테스트가 실패하여 커밋이 차단되었습니다: $d" >&2
      return 1
    fi
  done
  echo "[SUCCESS] Kyverno policy test passed."
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

  echo "--- Step: Prometheus Alerting Rule Validation ---"
  if ! has_tool promtool; then
    echo "[WARNING] PrometheusRule manifest found but 'promtool' is not installed. Skipping."
    return 0
  fi
  if ! has_tool yq; then
    echo "[WARNING] PrometheusRule manifest found but 'yq' is not installed (required to extract .spec from the CRD wrapper before promtool can parse it). Skipping."
    return 0
  fi

  for f in "${rule_files[@]}"; do
    echo "Checking PrometheusRule: $f"
    local tmp
    tmp=$(mktemp)
    # promtool은 순수 groups: 포맷만 이해하므로, CRD 래퍼(apiVersion/kind/metadata)를
    # 벗기고 spec 블록만 추출해 넘긴다.
    if ! yq eval '.spec' "$f" >"$tmp"; then
      echo "❌ [ERROR] PrometheusRule의 .spec 블록 추출에 실패했습니다: $f" >&2
      rm -f "$tmp"
      return 1
    fi
    if ! promtool check rules "$tmp"; then
      echo "❌ [ERROR] PromQL Alerting Rule 문법 검증에 실패하여 커밋이 차단되었습니다: $f" >&2
      rm -f "$tmp"
      return 1
    fi
    rm -f "$tmp"
  done
  echo "[SUCCESS] Prometheus rule validation passed."
}

# 3. Deprecated / Removed K8s API Detection
check_deprecated_apis() {
  # 스테이징된 yaml이 실제 K8s 매니페스트인지(kind: 존재) 먼저 걸러낸다. 이 필터가
  # 없으면 GitHub Actions workflow 등 무관한 yaml 수정만으로도 저장소 전체 pluto
  # 스캔이 트리거된다.
  local manifests=() f
  for f in "${GLOBAL_STAGED_YAML_FILES[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    grep -qE "^kind:" "$f" 2>/dev/null && manifests+=("$f")
  done
  if [ "${#manifests[@]}" -eq 0 ]; then
    return 0
  fi

  echo "--- Step: Deprecated K8s API Detection ---"
  if ! has_tool pluto; then
    echo "[WARNING] pluto is not installed. Skipping deprecated API scan."
    return 0
  fi

  if ! pluto detect-files -d .; then
    echo "❌ [ERROR] 삭제 예정(Deprecated/Removed) K8s API 버전이 감지되어 커밋이 차단되었습니다." >&2
    return 1
  fi
  echo "[SUCCESS] No deprecated/removed K8s API versions detected."
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

  echo "======================================================"
  echo "=== K8s-Specific Checks Passed Successfully ==="
  echo "======================================================"
}

main
