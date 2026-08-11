#!/usr/bin/env bash
# pre-flight-check.sh - Modular & Fail-safe IaC/Script Validation Pipeline

set -euo pipefail
export ANSIBLE_HOME="$HOME/.cache/ansible"

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
PFC_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$PFC_SCRIPT_DIR/../lib/script-init.sh"

log_info "============================================="
log_info "=== Pre-Flight Validation Pipeline Started ==="
log_info "============================================="

# -----------------------------------------------------------------------------
# Common Helpers
# -----------------------------------------------------------------------------
# git diff --cached의 pathspec이 CWD 기준으로 해석되어 오탐하는 것을 방지하기 위해 저장소 루트로 이동
init_repo_root
CACHE_FILE="$REPO_ROOT/.pre-flight-check.cache"

# 도구 가용성 조회 헬퍼 로드
# shellcheck source-path=SCRIPTDIR
source "$PFC_SCRIPT_DIR/../lib/tool-probe.sh"

calculate_tf_hash() {
  # staged 모드에서만 Git 인덱스 기반 캐싱 사용 (워킹트리 불변 시 거짓 통과 방지)
  if [ "$GLOBAL_CACHE_ENABLED" -ne 1 ]; then
    echo "disabled"
    return
  fi

  # main()에서 1회만 판정한 Git 저장소 여부 및 대상 .tf 목록을 재사용 (중복 git 호출 제거)
  if [ "$GLOBAL_IS_GIT_REPO" -ne 1 ]; then
    echo "non-git"
    return
  fi

  if [ "${#GLOBAL_TARGET_TF_FILES[@]}" -eq 0 ] || [ -z "${GLOBAL_TARGET_TF_FILES[0]}" ]; then
    echo "empty"
    return
  fi

  # Git Index(스테이징 영역)에 기록된 파일 오브젝트들의 SHA-1 해시 목록을 종합하여 대표 해시 생성
  git ls-files --stage "${GLOBAL_TARGET_TF_FILES[@]}" 2>/dev/null | sha256sum | awk '{print $1}'
}

# validate_terraform/validate_finops_costs 양쪽에 동일한 4줄짜리 캐시 히트 조건이
# 그대로 복붙돼 있던 것을 SSOT로 뽑아냈다. 로그 메시지는 두 함수의 문맥(Step 헤더
# 출력 시점이 다름)에 따라 달라 호출부에 그대로 남긴다.
# stdout: "empty"(스테이징된 .tf 없음) | "cached"(직전 성공 검증과 동일) | ""(캐시 미스)
tf_cache_status() {
  if [ "$GLOBAL_TF_HASH" = "empty" ]; then
    echo "empty"
  elif [ "$GLOBAL_CACHE_ENABLED" -eq 1 ] && [ -f "$CACHE_FILE" ] && [ "$GLOBAL_TF_HASH" != "non-git" ] && [ "$GLOBAL_TF_HASH" == "$(cat "$CACHE_FILE" 2>/dev/null)" ]; then
    echo "cached"
  fi
}

# -----------------------------------------------------------------------------
# Validation Sub-modules (도메인별로 분리된 파일을 source)
# -----------------------------------------------------------------------------
# 검증 로직은 bin/lib/pfc-iac-checks.sh / pfc-quality-checks.sh로 분리했고, 오케스트레이션만
# 이 파일에 남겼다. 두 파일 모두 위에서 정의한 전역 상태를 source로 그대로 공유하므로,
# bin/linters/*.sh 와 달리 서브프로세스 간 상태 재직렬화가 필요 없다.
# shellcheck source-path=SCRIPTDIR
source "$PFC_SCRIPT_DIR/../lib/pfc-iac-checks.sh"
# shellcheck source-path=SCRIPTDIR
source "$PFC_SCRIPT_DIR/../lib/pfc-quality-checks.sh"

# 12. Skill-Specific Delegated Checks (auto-discovered)
# 범용성 유지를 위해 플러그인 폴더(bin/hooks/plugins/*.sh) 내 검증 스크립트를 동적 로드
run_delegated_skill_checks() {
  # yaml 변경이 없을 경우 위임 검증 생략 (프로세스 오버헤드 절감)
  if [ "${#GLOBAL_TARGET_YAML_FILES[@]}" -eq 0 ] || [ -z "${GLOBAL_TARGET_YAML_FILES[0]}" ]; then
    return 0
  fi

  # 첫 실패에서 즉시 중단하면 뒤 플러그인은 실행조차 안 된다. 플러그인끼리는 각자
  # git diff --cached를 독립적으로 재조회해 상태를 공유하지 않으므로 순서와 무관하게
  # 끝까지 돌려도 안전하다. 같은 파일이 여러 플러그인의 대상이 될 수 있어(예:
  # PrometheusRule YAML은 k8s-check.sh와 observability-check.sh 양쪽에 다 걸림), 첫
  # 플러그인만 보고하면 두 번째 위반은 재커밋해야 발견된다. run-suite.sh의 스크립트 간
  # 판정과 동일한 관용구를 여기 플러그인 간에도 적용한다.
  # 플러그인에 이번 실행의 검사 대상을 인자로 넘긴다. 예전엔 인자 없이 호출했고 플러그인이
  # 저마다 git diff --cached 를 하드코딩해, --all/--changed/explicit 모드에서는 실행 모드와
  # 무관하게 항상 "스테이징된 것"만 봤다 — 즉 just verify(--all)나
  # pre-flight-live-hook.sh(explicit)에서는 위임 검증이 통째로 비어 있으면서 초록불만 떴다
  # (실측 재현: bin/lib/plugin-targets.sh 헤더 주석 참조).
  #
  # 넘기는 목록은 filter_target_files 를 거친 것이라 */tests/* 가 이미 빠져 있다. 의도적
  # 위반을 담은 회귀 테스트 픽스처가 --all 스캔에서 잡혀 무관한 커밋을 막는 일을 방지한다.
  # 세 플러그인이 보는 확장자의 합집합을 넘기고, 그 안에서 무엇을 볼지는 종전대로 각
  # 플러그인이 자기 패턴으로 다시 좁힌다.
  local plugin_targets=()
  mapfile -d '' -t plugin_targets < <(filter_target_files '*.yaml' '*.yml' '*.json' '*.tf')

  local skill_script rc failed=0
  shopt -s nullglob
  for skill_script in "$PFC_SCRIPT_DIR/plugins"/*.sh; do
    rc=0
    bash "$skill_script" "${plugin_targets[@]}" || rc=$?
    [ "$rc" -ne 0 ] && failed=1
  done
  shopt -u nullglob
  [ "$failed" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Main Orchestration Flow
# -----------------------------------------------------------------------------
# 전역 캐시 변수 선언 (쉘 연산 호출 중복 제거)
GLOBAL_IS_GIT_REPO=0
GLOBAL_TF_HASH=""
GLOBAL_TARGET_TF_FILES=()
GLOBAL_TARGET_YAML_FILES=()

# 검증 대상은 main()에서 한 번만 수집하고, 각 검증 함수는 filter_target_files 로 자기
# 확장자만 골라 쓴다(수집-필터링 분리). 이 구조 덕에 staged 외의 changed/all/explicit
# 수집 모드도 함수 수정 없이 그대로 지원된다.
GLOBAL_TARGET_FILES=()
# 대상 수집 모드: staged(기본) | changed | all | explicit
GLOBAL_TARGET_MODE="staged"
# Terraform 캐시 활성 여부. 인덱스 기준 해시라 staged 모드에서만 성립한다(calculate_tf_hash 주석 참조).
GLOBAL_CACHE_ENABLED=0

print_usage() {
  cat >&2 <<'USAGE'
사용법: pre-flight-check.sh [모드 | 파일...]

  (인자 없음)   스테이징된 변경분만 검증한다 (커밋 훅과 동일한 기본 동작).
  --changed     스테이징 + 미스테이징 + untracked 변경분을 모두 검증한다.
  --unstaged    --changed 의 하위 호환 별칭.
  --all         저장소의 tracked + untracked 파일 전체를 검증한다 (회귀 검사용).
  <파일...>     지정한 경로만 대상으로 삼는다. 존재하지 않으면 즉시 실패한다.
                (주의: terraform fmt/validate 는 디렉토리 단위로 동작하므로 파일 지정은
                 "검증을 켤지"의 게이트일 뿐 스캔 범위를 좁히지 못한다.)
USAGE
}

filter_target_files() {
  local pattern f
  for f in "${GLOBAL_TARGET_FILES[@]}"; do
    [ -z "$f" ] && continue
    # 테스트 관련 파일(픽스처 등)은 전역 린트 대상에서 원천 제외
    if [[ "$f" == */tests/* ]] || [[ "$f" == tests/* ]]; then
      continue
    fi
    for pattern in "$@"; do
      # 우변은 글롭 패턴이므로 의도적으로 인용하지 않는다(git pathspec 과 동등한 매칭).
      # shellcheck disable=SC2053
      if [[ "$f" == $pattern ]]; then
        printf '%s\0' "$f"
        break
      fi
    done
  done
}

# NUL 구분 스트림 중복 제거 (워킹트리에 존재하는 파일만 필터링)
collect_target_files() {
  local -A seen=()
  local f
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    [ -n "${seen[$f]:-}" ] && continue
    seen["$f"]=1
    [ -e "$f" ] || continue
    GLOBAL_TARGET_FILES+=("$f")
  done
}

# 옵션 인자 파싱 및 실행 모드(staged/changed/all/explicit) 확정
# 존재하지 않는 경로는 조용히 건너뛰지 않고 즉시 중단(오탐 방지)
parse_target_args() {
  local arg
  if [ $# -eq 0 ]; then
    GLOBAL_TARGET_MODE="staged"
    return 0
  fi

  case "$1" in
  --help | -h)
    print_usage
    exit 0
    ;;
  --all | --changed | --unstaged)
    if [ $# -gt 1 ]; then
      echo "[ERROR] '$1' 은 다른 인자와 함께 사용할 수 없습니다." >&2
      print_usage
      exit 2
    fi
    if [ "$1" = "--all" ]; then
      GLOBAL_TARGET_MODE="all"
    else
      GLOBAL_TARGET_MODE="changed"
    fi
    ;;
  --*)
    echo "[ERROR] 알 수 없는 옵션입니다: $1" >&2
    print_usage
    exit 2
    ;;
  *)
    GLOBAL_TARGET_MODE="explicit"
    for arg in "$@"; do
      if [[ "$arg" == --* ]]; then
        echo "[ERROR] 알 수 없는 옵션입니다: $arg" >&2
        print_usage
        exit 2
      fi
      if [ ! -e "$arg" ]; then
        echo "[ERROR] 검증 대상 경로를 찾을 수 없습니다: $arg" >&2
        exit 1
      fi
      GLOBAL_TARGET_FILES+=("$arg")
    done
    ;;
  esac
}

main() {
  parse_target_args "$@"

  if git rev-parse --is-inside-work-tree &>/dev/null; then
    GLOBAL_IS_GIT_REPO=1
  fi

  case "$GLOBAL_TARGET_MODE" in
  staged)
    if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
      GLOBAL_CACHE_ENABLED=1
      collect_target_files < <(git diff --cached --name-only -z --diff-filter=ACM 2>/dev/null)
    else
      # 대상 0건으로 조용히 통과하지 않도록 경고를 남긴다. 파일을 직접 지정하면 검증된다.
      echo "[WARNING] Git 저장소가 아니어서 스테이징 기준 대상이 없습니다. 검증할 경로를 인자로 지정하십시오." >&2
    fi
    ;;
  changed | all)
    if [ "$GLOBAL_IS_GIT_REPO" -ne 1 ]; then
      echo "[ERROR] '--$GLOBAL_TARGET_MODE' 모드는 Git 저장소 안에서만 사용할 수 있습니다." >&2
      exit 1
    fi
    if [ "$GLOBAL_TARGET_MODE" = "all" ]; then
      collect_target_files < <(
        git ls-files -z 2>/dev/null
        git ls-files -z --others --exclude-standard 2>/dev/null
      )
    else
      collect_target_files < <(
        git diff --cached --name-only -z --diff-filter=ACM 2>/dev/null
        git diff --name-only -z --diff-filter=ACM 2>/dev/null
        git ls-files -z --others --exclude-standard 2>/dev/null
      )
    fi
    if [ "${#GLOBAL_TARGET_FILES[@]}" -eq 0 ]; then
      echo "[WARNING] '--$GLOBAL_TARGET_MODE' 대상 파일이 0건입니다. 검증이 수행되지 않았습니다." >&2
    fi
    ;;
  esac

  mapfile -d '' -t GLOBAL_TARGET_TF_FILES < <(filter_target_files '*.tf')
  mapfile -d '' -t GLOBAL_TARGET_YAML_FILES < <(filter_target_files '*.yaml' '*.yml')

  # calculate_tf_hash는 위에서 채운 GLOBAL_IS_GIT_REPO/GLOBAL_TARGET_TF_FILES를 재사용한다.
  GLOBAL_TF_HASH=$(calculate_tf_hash)

  validate_shell
  validate_terraform
  validate_sam
  validate_bicep
  validate_ansible
  validate_helm
  validate_k8s_manifests
  validate_docker
  validate_yaml
  validate_conftest
  validate_security
  validate_finops_costs
  run_delegated_skill_checks

  # 검증 성공 시 스테이징 캐시 갱신 (쓰기 실패 시 무시, 동시 실행 시 원자적 덮어쓰기로 캐시 파일 손상 방지)
  if [ "$GLOBAL_CACHE_ENABLED" -eq 1 ] && [ "$GLOBAL_TF_HASH" != "empty" ] && [ "$GLOBAL_TF_HASH" != "non-git" ]; then
    cache_tmp=$(mktemp "$REPO_ROOT/.pre-flight-check.cache.XXXXXX" 2>/dev/null) || cache_tmp=""
    if [ -n "$cache_tmp" ]; then
      echo "$GLOBAL_TF_HASH" >"$cache_tmp" 2>/dev/null && mv "$cache_tmp" "$CACHE_FILE" 2>/dev/null || rm -f "$cache_tmp" 2>/dev/null || true
    fi
  fi

  log_info "================================================="
  log_info "=== All Pre-Flight Checks Passed Successfully ==="
  print_unavailable_tools
  log_info "================================================="
}

# Run execution
main "$@"
