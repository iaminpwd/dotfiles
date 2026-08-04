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
# Validation Sub-modules (Isolated Functions)
# -----------------------------------------------------------------------------

# 1. Shell Script Validation
validate_shell() {
  # 지정된 범위 내의 확장자(.sh/.zsh) 파일, Git 훅 스크립트, 셸 설정 파일만 검사
  local shell_files=()
  mapfile -d '' -t shell_files < <(filter_target_files '*.sh' '*.zsh' '*.zshrc' '*.zshenv' '*/.githooks/*')

  if [ "${#shell_files[@]}" -eq 0 ] || [ -z "${shell_files[0]}" ]; then
    log_info "--- Step: Shell Script Validation ---"
    log_info "[INFO] No staged shell script changes detected. Skipping shell validation."
    return 0
  fi

  log_info "--- Step: Shell Script Validation ---"

  # zsh 방언은 shfmt/shellcheck 호환이 안 되므로 zsh -n 구문 검사만 수행
  local sh_only_files=() zsh_files=()
  for f in "${shell_files[@]}"; do
    [ -z "$f" ] && continue
    case "$f" in
    *.zsh | *.zshrc | *.zshenv) zsh_files+=("$f") ;;
    *) sh_only_files+=("$f") ;;
    esac
  done

  # 오탐 경고를 막기 위해 해당 검사 파일이 존재할 때만 도구 설치 여부 확인
  local has_shfmt=0 has_zsh=0 has_shellcheck=0
  if [ "${#sh_only_files[@]}" -gt 0 ]; then
    if has_tool shfmt; then has_shfmt=1; fi
    if has_tool shellcheck; then has_shellcheck=1; fi

    # shfmt가 존재하면 루프 밖에서 일괄 포맷 체크 (프로세스 오버헤드 절감)
    if [ "$has_shfmt" -eq 1 ]; then
      log_info "Checking format for all shell scripts..."
      if ! shfmt -d -i 2 "${sh_only_files[@]}"; then
        echo "❌ [ERROR] shfmt 포맷이 맞지 않아 커밋이 중단되었습니다. 'shfmt -w -i 2 <파일>'로 정리한 뒤 다시 시도하세요." >&2
        return 1
      fi
    fi

    if [ "$has_shellcheck" -eq 1 ]; then
      log_info "Running shellcheck..."
      # -x: source 로 불러오는 라이브러리까지 따라가 분석한다. 없으면 라이브러리를 쓰는
      # 스크립트마다 SC1091("not specified as input")이 info 로 뜨고, shellcheck 는 지적이
      # 하나라도 있으면 exit 1 이므로 정상 코드가 커밋 중단으로 이어진다(2026-07-28 실측:
      # tool-probe.sh 분리 직후 k8s-check.sh 가 exit 1). 따라가는 편이 분석 품질도 낫다.
      if ! shellcheck -x "${sh_only_files[@]}"; then
        echo "❌ [ERROR] shellcheck 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
    else
      log_info "[WARNING] shellcheck is not installed. Skipping static analysis for shell scripts."
    fi
  fi

  if [ "${#zsh_files[@]}" -gt 0 ] && has_tool zsh; then has_zsh=1; fi

  # zsh 방언 파일은 zsh -n 이 유일한 검증 수단이므로, zsh 가 없으면 이 파일들은 아무 검사도
  # 받지 못한 채 통과한다. 그 사실을 UNAVAILABLE_TOOLS 요약에 실어 무검증 통과를 드러낸다.
  for f in "${zsh_files[@]}"; do
    log_info "Checking syntax: $f"
    if [ "$has_zsh" -eq 1 ]; then
      if ! zsh -n "$f"; then
        echo "❌ [ERROR] zsh 문법 오류가 발견되어 커밋이 중단되었습니다: $f" >&2
        return 1
      fi
    else
      log_info "[WARNING] zsh not found, skipping syntax check for: $f"
    fi
  done

  for f in "${sh_only_files[@]}"; do
    log_info "Checking syntax: $f"
    if ! bash -n "$f"; then
      echo "❌ [ERROR] bash 문법 오류가 발견되어 커밋이 중단되었습니다: $f" >&2
      return 1
    fi
  done

  # Idempotency Static Analysis
  # PFC_SCRIPT_DIR은 readlink -f로 심볼릭 링크를 완전히 해소한 경로(bin/hooks)라,
  # 어떤 배포 경로로 호출돼도 항상 실제 원본 위치 기준으로 상대 이동한다.
  local IDEMPOTENCY_SCRIPT="$PFC_SCRIPT_DIR/../linters/idempotency-check.sh"
  if [ -f "$IDEMPOTENCY_SCRIPT" ]; then
    bash "$IDEMPOTENCY_SCRIPT" "${shell_files[@]}" || true
  fi

  log_info "[SUCCESS] Shell scripts validation passed."
}

# 2. Terraform Validation
validate_terraform() {
  # 검증 대상 중 .tf 파일만 검사 (fmt/validate는 디렉토리 단위 동작이므로 실행 여부만 결정)
  local tf_files=("${GLOBAL_TARGET_TF_FILES[@]}")

  if [ "${#tf_files[@]}" -gt 0 ] && [ -n "${tf_files[0]}" ]; then
    log_info "--- Step: Terraform Validation ---"

    # 스테이징 영역 캐시 확인 (staged 모드 전용. 워킹트리 모드에서는 GLOBAL_CACHE_ENABLED=0)
    case "$(tf_cache_status)" in
    empty)
      log_info "[INFO] No staged Terraform changes detected. Skipping Terraform validation (Cache hit - empty)."
      return 0
      ;;
    cached)
      log_info "[INFO] Staged Terraform configuration is unchanged. Skipping Terraform validation (Cache hit)."
      return 0
      ;;
    esac
    if ! has_tool terraform; then
      echo "[ERROR] terraform CLI is required but not installed." >&2
      return 1
    fi

    log_info "Running terraform fmt check..."
    # shfmt와 동일하게 루프 밖에서 일괄 포맷 체크 (프로세스 오버헤드 절감).
    # terraform fmt -check는 포맷이 안 맞는 파일명을 자체적으로 stdout에 출력하므로
    # 파일별 개별 echo 없이도 어떤 파일이 문제인지 그대로 드러난다.
    local tf_fmt_targets=()
    for tf in "${tf_files[@]}"; do
      [ -z "$tf" ] && continue
      [[ "$tf" == */tests/fixtures/* ]] && continue
      tf_fmt_targets+=("$tf")
    done
    if [ "${#tf_fmt_targets[@]}" -gt 0 ] && ! terraform fmt -check "${tf_fmt_targets[@]}"; then
      echo "❌ [ERROR] terraform fmt 포맷이 맞지 않아 커밋이 중단되었습니다. 'terraform fmt -recursive'로 정리한 뒤 다시 시도하세요." >&2
      return 1
    fi

    log_info "Running terraform validate (offline initialization)..."
    if [ ! -d ".terraform" ]; then
      if ! terraform init -backend=false -input=false >/dev/null; then
        echo "❌ [ERROR] terraform init 초기화에 실패하여 커밋이 중단되었습니다." >&2
        return 1
      fi
    fi
    if ! terraform validate; then
      echo "❌ [ERROR] terraform validate 검증에 실패하여 커밋이 중단되었습니다." >&2
      return 1
    fi

    if has_tool tflint; then
      log_info "Running tflint..."
      if [ -f ".tflint.hcl" ] || [ -f "$HOME/.tflint.hcl" ]; then
        tflint --init || true
      fi
      if ! tflint; then
        echo "❌ [ERROR] tflint 정적 분석에서 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
    else
      log_info "[WARNING] tflint is not installed. Skipping static analysis."
    fi

    if has_tool checkov; then
      # tflint가 잡지 못하는 보안 오구성(Security Misconfiguration) 검사
      # OSS checkov는 심각도 필터가 미지원되어, 하나라도 지적 시 커밋이 중단됨
      log_info "Running checkov (Terraform security misconfiguration scan)..."
      if ! checkov --directory . --framework terraform --compact --quiet --soft-fail-on LOW,MEDIUM --skip-path contexts/aws/tests/fixtures --skip-path contexts/azure/tests/fixtures --skip-path contexts/openstack/tests/fixtures --skip-path contexts/k8s/tests/fixtures; then
        echo "❌ [ERROR] checkov에서 HIGH/CRITICAL 등급의 보안 오구성이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
    else
      log_info "[WARNING] checkov is not installed. Skipping IaC security misconfiguration scan."
    fi

    if [ -x "$PFC_SCRIPT_DIR/../linters/db-sg-checker.sh" ]; then
      log_info "Running DB SG architecture check..."
      if ! bash "$PFC_SCRIPT_DIR/../linters/db-sg-checker.sh" .; then
        echo "❌ [ERROR] DB 보안 그룹 아키텍처 위반(Web/WAS SG 미지정)으로 커밋이 중단되었습니다." >&2
        return 1
      fi
    fi

    log_info "[SUCCESS] Terraform validation passed."
  fi
}

# 3. AWS SAM Validation
validate_sam() {
  # 서브디렉토리 템플릿 탐지를 위해 git pathspec을 활용해 스테이징된 파일 스캔
  local sam_templates=()
  mapfile -d '' -t sam_templates < <(filter_target_files '*template.yaml' '*template.yml')

  if [ "${#sam_templates[@]}" -eq 0 ] || [ -z "${sam_templates[0]}" ]; then
    return 0
  fi

  if ! has_tool sam; then
    log_info "--- Step: AWS SAM Validation ---"
    log_info "[WARNING] SAM templates found but sam CLI is not installed."
    return 0
  fi

  log_info "--- Step: AWS SAM Validation ---"
  for tpl in "${sam_templates[@]}"; do
    [ -z "$tpl" ] && continue
    log_info "Validating SAM template: $tpl"
    if ! sam validate --template-file "$tpl"; then
      echo "❌ [ERROR] SAM 템플릿 검증에 실패하여 커밋이 중단되었습니다: $tpl" >&2
      return 1
    fi
  done
  log_info "[SUCCESS] SAM template validation passed."
}

# 3b. Azure Bicep Validation (3. AWS SAM 과 같은 계열: 클라우드 네이티브 템플릿)
validate_bicep() {
  local bicep_files=()
  mapfile -d '' -t bicep_files < <(filter_target_files '*.bicep')

  if [ "${#bicep_files[@]}" -eq 0 ] || [ -z "${bicep_files[0]}" ]; then
    return 0
  fi

  # Bicep(.NET 기반)이 libicu가 없는 Linux 환경에서도 정상 실행되도록 Invariant 모드 강제 활성화
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

  local has_bicep=0
  if has_tool bicep && bicep --version &>/dev/null 2>&1; then
    has_bicep=1
  elif has_tool az && az bicep version &>/dev/null 2>&1; then
    has_bicep=2
  fi
  if [ "$has_bicep" -eq 0 ]; then
    log_info "--- Step: Azure Bicep Validation ---"
    log_info "[WARNING] Bicep files found but neither standalone 'bicep' CLI nor 'az bicep' is installed."
    return 0
  fi

  log_info "--- Step: Azure Bicep Validation ---"
  local bicep_cmd="none"
  if [ "$has_bicep" -eq 1 ]; then
    bicep_cmd="standalone"
  elif [ "$has_bicep" -eq 2 ]; then
    bicep_cmd="az"
  fi

  for bf in "${bicep_files[@]}"; do
    [ -z "$bf" ] && continue
    log_info "Validating bicep file: $bf"

    if [ "$bicep_cmd" = "standalone" ]; then
      if ! bicep build "$bf" --stdout >/dev/null; then
        echo "❌ [ERROR] Bicep 템플릿 검증에 실패하여 커밋이 중단되었습니다: $bf" >&2
        return 1
      fi
    elif [ "$bicep_cmd" = "az" ]; then
      if ! az bicep build --file "$bf" --stdout >/dev/null; then
        echo "❌ [ERROR] Bicep 템플릿 검증에 실패하여 커밋이 중단되었습니다: $bf" >&2
        return 1
      fi
    else
      echo "❌ [ERROR] Bicep 실행 파일을 찾을 수 없거나 실행이 미지원능합니다(OS 호환성 문제 등). 커밋이 중단되었습니다." >&2
      return 1
    fi
  done
  log_info "[SUCCESS] Bicep validation passed."
}

# 4. Ansible Validation
validate_ansible() {
  # 서브디렉토리 구성 지원을 위해 글롭(*)을 사용하여 Ansible 파일 스캔
  local ansible_files=() staged_roles=()
  mapfile -d '' -t ansible_files < <(filter_target_files '*playbook*.yml' '*playbook*.yaml' '*site.yml' '*site.yaml')
  mapfile -d '' -t staged_roles < <(filter_target_files '*roles/*')

  if { [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ]; } || { [ "${#staged_roles[@]}" -gt 0 ] && [ -n "${staged_roles[0]}" ]; }; then
    log_info "--- Step: Ansible Validation ---"
    if has_tool ansible-playbook && [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ]; then
      for pf in "${ansible_files[@]}"; do
        [ -z "$pf" ] && continue
        log_info "Checking ansible syntax: $pf"
        if ! ansible-playbook --syntax-check "$pf"; then
          echo "❌ [ERROR] Ansible 플레이북 문법 검사에 실패하여 커밋이 중단되었습니다: $pf" >&2
          return 1
        fi
      done
    fi
    if has_tool ansible-lint; then
      log_info "Running ansible-lint..."
      local lint_cmd=(ansible-lint)
      if ! "${lint_cmd[@]}"; then
        echo "❌ [ERROR] ansible-lint 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        rm -rf .ansible
        return 1
      fi
      rm -rf .ansible
      log_info "✅ ansible-lint passed."
    else
      log_info "[WARNING] ansible-lint is not installed. Skipping lint validation."
    fi
  fi
}

# 5. K8s Helm Validation
validate_helm() {
  # 서브디렉토리 차트 탐지를 위해 글롭(*) pathspec으로 스테이징된 Helm 관련 파일 스캔
  local helm_changed=()
  mapfile -d '' -t helm_changed < <(filter_target_files '*Chart.yaml' '*values.yaml' '*/templates/*')
  if [ "${#helm_changed[@]}" -eq 0 ] || [ -z "${helm_changed[0]}" ]; then
    return 0
  fi

  if ! has_tool helm; then
    log_info "--- Step: Helm Chart Validation ---"
    log_info "[WARNING] Chart.yaml found but helm CLI is not installed."
    return 0
  fi

  # 변경된 파일들이 속한 차트 디렉토리(Chart.yaml이 있는 저장소 내 위치)를 중복 없이 수집
  local chart_files=() chart_dirs=() cf d found existing
  mapfile -d '' -t chart_files < <(git ls-files -z -- '*Chart.yaml' 2>/dev/null)
  for cf in "${chart_files[@]}"; do
    [ -z "$cf" ] && continue
    d=$(dirname "$cf")
    found=0
    for hf in "${helm_changed[@]}"; do
      [ "$hf" = "$d/Chart.yaml" ] && found=1 && break
      [[ "$hf" == "$d"/* ]] && found=1 && break
    done
    [ "$found" -eq 0 ] && continue
    for existing in "${chart_dirs[@]:-}"; do
      [ "$existing" = "$d" ] && found=2 && break
    done
    [ "$found" -eq 2 ] && continue
    chart_dirs+=("$d")
  done

  if [ "${#chart_dirs[@]}" -eq 0 ]; then
    return 0
  fi

  log_info "--- Step: Helm Chart Validation ---"
  for d in "${chart_dirs[@]}"; do
    log_info "Linting chart: $d"
    if ! helm lint "$d"; then
      echo "❌ [ERROR] Helm lint 지적 사항이 발견되어 커밋이 중단되었습니다: $d" >&2
      return 1
    fi
  done
  log_info "[SUCCESS] Helm lint passed."
}

# 6. Raw K8s Manifest Validation
validate_k8s_manifests() {
  # main()에서 1회만 조회한 스테이징 YAML 목록을 재사용 (validate_yaml과 중복 git diff 호출 최소화)
  local staged_yaml=("${GLOBAL_TARGET_YAML_FILES[@]}")

  # Helm 차트의 templates/ 하위는 Go 템플릿이 혼재되어 YAML 검증에서 제외 (helm lint 위임)
  local k8s_manifests=()
  for f in "${staged_yaml[@]}"; do
    [ -z "$f" ] && continue
    [[ "$f" == */templates/* ]] && continue
    [ -f "$f" ] || continue
    grep -qE "^kind:" "$f" 2>/dev/null && k8s_manifests+=("$f")
  done

  if [ "${#k8s_manifests[@]}" -gt 0 ] && [ -n "${k8s_manifests[0]}" ]; then
    log_info "--- Step: K8s Manifest Validation ---"
    if has_tool kube-linter; then
      log_info "Running kube-linter for all manifests..."
      if ! kube-linter lint "${k8s_manifests[@]}"; then
        echo "❌ [ERROR] kube-linter 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
      log_info "[SUCCESS] kube-linter passed."
    elif has_tool kubectl; then
      log_info "Running kubectl --dry-run (client-side) for manifest validation..."
      for mf in "${k8s_manifests[@]}"; do
        [ -z "$mf" ] && continue
        echo "Validating: $mf"
        if ! kubectl apply --dry-run=client -f "$mf" 2>&1; then
          echo "❌ [ERROR] kubectl dry-run 검증에 실패하여 커밋이 중단되었습니다: $mf" >&2
          return 1
        fi
      done
      log_info "[SUCCESS] kubectl dry-run validation passed."
    else
      log_info "[WARNING] K8s manifests found but neither kube-linter nor kubectl is installed."
    fi
  fi
}

# 7. Dockerfile Validation
validate_docker() {
  local dockerfiles=()
  mapfile -d '' -t dockerfiles < <(filter_target_files '*Dockerfile*')

  if [ "${#dockerfiles[@]}" -gt 0 ] && [ -n "${dockerfiles[0]}" ]; then
    if has_tool hadolint; then
      log_info "--- Step: Dockerfile Validation ---"
      log_info "Linting Dockerfiles..."
      if ! hadolint "${dockerfiles[@]}"; then
        echo "❌ [ERROR] hadolint 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
      log_info "[SUCCESS] Dockerfile validation passed."
    else
      log_info "[WARNING] Dockerfiles found but hadolint is not installed."
    fi

    # DS-0002(컨테이너가 root로 실행됨) 하드 블록. hadolint에는 이 룰이 없다(2026-08-04
    # 실측: hadolint 2.12.0이 USER 누락 Dockerfile을 무관한 경고만 내고 통과시킴).
    # validate_security()의 trivy misconfig 스캔이 같은 DS-0002를 이미 경고로는
    # 잡고 있었지만, db-sg-checker.sh(DB 포트 0.0.0.0/0 노출)와 같은 급의 오탐 거의
    # 없는 기초 항목이라 다른 하드 게이트들과 같은 강제력으로 맞춘다. container-
    # hardening-gate.sh는 파일 경로를 받으면 trivy conf로 그 경로만 검사하고 이미지
    # 스캔 분기(dive/trivy image, 릴리즈 단계 책임)는 타지 않는다.
    local HARDENING_SCRIPT="$PFC_SCRIPT_DIR/../linters/container-hardening-gate.sh"
    if [ -x "$HARDENING_SCRIPT" ]; then
      local dockerfile
      for dockerfile in "${dockerfiles[@]}"; do
        if ! bash "$HARDENING_SCRIPT" "$dockerfile"; then
          echo "❌ [ERROR] $dockerfile 컨테이너 하드닝 검사(DS-0002)에 실패하여 커밋이 중단되었습니다." >&2
          return 1
        fi
      done
    fi

    # 여기에는 예전에 syft(소스 SBOM 생성)와 grype(의존성 CVE 스캔)의 `dir:.` 소스 스캔이
    # 있었으나 제거했다. 두 도구가 보던 대상(requirements.txt/package.json/go.mod 등 의존성
    # 매니페스트)은 validate_security 의 `trivy fs --scanners vuln` 이 이미 같은 저장소를
    # 훑으며 검사한다. 둘 다 --exit-code 0 상당의 경고 전용이라 중단력이 겹치는 것도 아니고,
    # 특히 syft 는 게이트가 아니라 SBOM 테이블을 stdout 에 통째로 출력할 뿐이어서 Dockerfile
    # 을 건드린 커밋마다 순수 노이즈만 남겼다. 취약점 DB가 서로 달라 검출 결과가 완전히
    # 같지는 않지만, 커밋 시점에 경고 전용 스캐너를 두 개 돌릴 근거로는 약하다.
    #
    # 이미지 레이어 취약점(vuln/SBOM/서명) 검사는 릴리즈 단계 책임이므로 제외
  fi
}

# 8. YAML Style & Validation (Relaxed / Fail-safe)
validate_yaml() {
  # main()에서 1회만 조회한 스테이징 YAML 목록을 재사용 (validate_k8s_manifests와 중복 git diff 호출 최소화)
  local staged_yaml=("${GLOBAL_TARGET_YAML_FILES[@]}")

  # Helm 차트의 templates/ 하위는 Go 템플릿 구문이 섞여 있어 순수 YAML 린터(yamllint) 검증 대상에서 제외
  local yaml_files=()
  for f in "${staged_yaml[@]}"; do
    [ -z "$f" ] && continue
    [[ "$f" == */templates/* ]] && continue
    yaml_files+=("$f")
  done

  if [ "${#yaml_files[@]}" -gt 0 ] && [ -n "${yaml_files[0]}" ]; then
    if has_tool yamllint; then
      log_info "--- Step: YAML Style Validation (Relaxed) ---"
      # find로 필터링된 모든 YAML 파일을 일괄 검사
      if ! yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${yaml_files[@]}"; then
        echo "❌ [ERROR] yamllint 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
      log_info "[SUCCESS] YAML format validation passed."
    else
      log_info "[WARNING] YAML files found but yamllint is not installed."
    fi
  fi
}

# 9. OPA/Conftest Policy Validation
validate_conftest() {
  local staged_rego=() staged_config=()
  mapfile -d '' -t staged_rego < <(filter_target_files '*.rego')
  mapfile -d '' -t staged_config < <(filter_target_files '*.yaml' '*.yml' '*.json')

  local has_staged_rego=0 has_staged_config=0
  { [ "${#staged_rego[@]}" -gt 0 ] && [ -n "${staged_rego[0]}" ]; } && has_staged_rego=1
  { [ "${#staged_config[@]}" -gt 0 ] && [ -n "${staged_config[0]}" ]; } && has_staged_config=1

  # 서브디렉토리 정책 탐지를 위해 추적 중인 .rego 파일 존재 여부로 검사 활성화 판정
  local has_any_rego=0
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ] && [ -n "$(git ls-files -- '*.rego' 2>/dev/null)" ]; then
    has_any_rego=1
  fi

  if [ "$has_staged_rego" -eq 1 ] || { [ "$has_any_rego" -eq 1 ] && [ "$has_staged_config" -eq 1 ]; }; then
    if has_tool conftest; then
      log_info "--- Step: Conftest Policy Validation ---"

      # 서브디렉토리 정책 적용을 위해 .rego 파일이 위치한 모든 디렉토리를 --policy 로 명시
      local rego_files=() policy_dirs=() rf pd found existing
      mapfile -d '' -t rego_files < <(git ls-files -z -- '*.rego' 2>/dev/null)
      for rf in "${rego_files[@]}"; do
        [ -z "$rf" ] && continue
        pd=$(dirname "$rf")
        found=0
        for existing in "${policy_dirs[@]:-}"; do
          [ "$existing" = "$pd" ] && found=1 && break
        done
        [ "$found" -eq 0 ] && policy_dirs+=("$pd")
      done
      local policy_flags=()
      for pd in "${policy_dirs[@]}"; do
        policy_flags+=(--policy "$pd")
      done

      if [ "$has_staged_rego" -eq 1 ]; then
        # 정책 변경 시 기존 리소스의 회귀(regression) 방지를 위해 전체 저장소 재검사
        log_info "[INFO] Rego policy changed. Testing against the entire repository for regressions."
        if ! conftest test "${policy_flags[@]}" .; then
          echo "❌ [ERROR] Conftest 정책 위반이 발견되어 커밋이 중단되었습니다." >&2
          return 1
        fi
      else
        # 리소스만 변경 시 해당 리소스만 검사하여 성능 최적화
        if ! conftest test "${policy_flags[@]}" "${staged_config[@]}"; then
          echo "❌ [ERROR] Conftest 정책 위반이 발견되어 커밋이 중단되었습니다." >&2
          return 1
        fi
      fi
      log_info "[SUCCESS] Conftest validation passed."
    else
      log_info "[WARNING] Rego policies found but conftest is not installed."
    fi
  fi
}

# 10. Security & Secret Scan
validate_security() {
  log_info "--- Step: Security and Secret Scan ---"
  if has_tool trivy; then
    log_info "Running trivy fs scan..."

    # 24시간(86400초) 수명 주기 정책 설정
    local db_ttl=86400
    local timestamp_file="$REPO_ROOT/.agent-state/trivy-db-update.timestamp"
    local skip_flags=()

    local now
    now=$(date +%s)

    if [ -f "$timestamp_file" ]; then
      local last_update
      last_update=$(cat "$timestamp_file" 2>/dev/null || echo 0)
      # 타임스탬프 손상 시 bash 산술 연산 오류 방지를 위해 0으로 폴백
      if ! [[ "$last_update" =~ ^[0-9]+$ ]]; then
        last_update=0
      fi
      local age=$((now - last_update))

      # 캐시 수명이 아직 유효한 경우 업데이트 스킵 플래그 동적 주입
      if [ "$age" -lt "$db_ttl" ]; then
        log_info "[INFO] Trivy DB cache is still valid ($((age / 3600))h old). Skipping DB update."
        skip_flags=(--skip-db-update --skip-check-update)
      fi
    fi

    # 1. 시크릿(비밀키, 토큰 등) 검사는 강제 중단 (exit-code 1)
    local tmp_secret
    tmp_secret=$(mktemp)
    if ! trivy fs -q "${skip_flags[@]}" --scanners secret --exit-code 1 . >"$tmp_secret" 2>&1; then
      cat "$tmp_secret"
      echo "❌ [ERROR] 시크릿(비밀키/토큰) 유출이 감지되어 커밋이 중단되었습니다."
      rm -f "$tmp_secret"
      return 1
    fi
    rm -f "$tmp_secret"
    log_info "[SUCCESS] Trivy secret scan passed."

    # 2. 취약점/오구성(vuln/misconfig) 경고 (커밋 중단 안함)
    # --skip-dirs: 의도적 위반을 담은 회귀 테스트 픽스처를 제외하여 노이즈 방지
    log_info "[INFO] Running trivy vulnerability & misconfig scan (Warnings only)..."
    local tmp_vuln
    tmp_vuln=$(mktemp)
    # Trivy --exit-code 0 시 출력 파싱으로 취약점 존재 여부 및 실행 실패 판별
    if trivy fs -q "${skip_flags[@]}" --severity HIGH,CRITICAL --scanners vuln,misconfig --exit-code 0 \
      --skip-dirs '**/tests/fixtures' . >"$tmp_vuln" 2>&1; then
      # 결과 테이블에 취약점이 있는지 확인 (Total: 0 이 아닌 경우)
      # Trivy 출력에 ANSI 색상 코드가 포함되어 있을 수 있으므로 제거 후 검사
      local clean_out
      clean_out=$(sed -r 's/\x1B\[[0-9;]*[mK]//g' "$tmp_vuln")
      if ! grep -qE "Total: 0 \(UNKNOWN: 0, LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 0\)" <<<"$clean_out" 2>/dev/null &&
        ! grep -q "'0': Clean (no security findings detected)" <<<"$clean_out" 2>/dev/null; then
        # 취약점이 있으면 출력
        cat "$tmp_vuln"
      fi
      rm -f "$tmp_vuln"
      log_info "[SUCCESS] Trivy vuln/misconfig scan passed."
    else
      cat "$tmp_vuln"
      rm -f "$tmp_vuln"
      log_info "[WARNING] Trivy vuln/misconfig scan failed to run (see output above). Continuing without blocking the commit."
    fi

    # 업데이트 진행 시 캐시 최신화 (쓰기 실패 시 무시, stderr 억제를 위해 리다이렉션 순서 주의)
    if [ "${#skip_flags[@]}" -eq 0 ]; then
      mkdir -p "$(dirname "$timestamp_file")" 2>/dev/null || true
      echo "$now" 2>/dev/null >"$timestamp_file" || true
    fi
  elif has_tool trufflehog; then
    log_info "Running trufflehog filesystem scan..."
    if ! trufflehog filesystem --no-update --fail .; then
      echo "❌ [ERROR] 시크릿(비밀키/토큰) 유출이 감지되어 커밋이 중단되었습니다."
      return 1
    fi
    log_info "[SUCCESS] Trufflehog secret scan passed."
  else
    log_info "[WARNING] Neither trivy nor trufflehog is installed. Skipping security scanning."
  fi
}

# 11. FinOps Cost Validation (Infracost)
validate_finops_costs() {
  # 커밋 시점이 아닐 경우 비용 검사 생략 (API 호출 한정 절약)
  if [ "${RUN_COST_CHECK:-false}" != "true" ]; then
    log_info "--- Step: FinOps Cost Validation (Infracost) ---"
    log_info "[INFO] Not in Git commit stage. Skipping cost validation to save API limits."
    return 0
  fi

  # main()에서 1회만 수집한 대상 .tf 목록을 재사용 (validate_terraform과 동일한 패턴)
  local tf_files=("${GLOBAL_TARGET_TF_FILES[@]}")

  if [ "${#tf_files[@]}" -gt 0 ] && [ -n "${tf_files[0]}" ]; then
    # 스테이징 영역 캐시 확인 (staged 모드 전용. 워킹트리 모드에서는 GLOBAL_CACHE_ENABLED=0)
    case "$(tf_cache_status)" in
    empty)
      log_info "--- Step: FinOps Cost Validation (Infracost) ---"
      log_info "[INFO] No staged Terraform changes detected. Skipping cost validation (Cache hit - empty)."
      return 0
      ;;
    cached)
      log_info "--- Step: FinOps Cost Validation (Infracost) ---"
      log_info "[INFO] Staged Terraform configuration is unchanged. Skipping cost validation (Cache hit)."
      return 0
      ;;
    esac
    if has_tool infracost; then
      log_info "--- Step: FinOps Cost Validation (Infracost) ---"
      log_info "Checking for AWS/Azure Extended Support & LTS pricing..."

      local cost_output_tmp
      cost_output_tmp=$(mktemp)
      # trap ... RETURN 은 bash에서 함수 스코프가 아니라 프로세스 전역이라, 이 함수가
      # 끝난 뒤에도 트랩이 남아 있다가 이후 리턴되는 다른 함수에서 발동해 이미 스코프를
      # 벗어난 $cost_output_tmp 를 참조하며 "unbound variable" 로 죽는 실사용 버그가
      # 있었다(2026-08-04 실측: RUN_COST_CHECK=true 실제 커밋 경로에서만 재현됨). 아래
      # 모든 종료 경로(679~690행)가 이미 rm -f 로 수동 정리하므로 트랩 없이도 누수가
      # 없다.

      # infracost breakdown을 수행하여 비용 항목 확인
      if infracost breakdown --path . >"$cost_output_tmp" 2>/dev/null; then
        if grep -E -qi "Extended Support|Long Term Support|LTS" "$cost_output_tmp"; then
          echo "[ERROR] Extended Support 또는 LTS (연장 지원) 추가 요금이 발생하는 리소스가 감지되었습니다." >&2
          echo "검출된 유효 비용 항목:" >&2
          grep -E -i "Extended Support|Long Term Support|LTS" "$cost_output_tmp" >&2
          rm -f "$cost_output_tmp"
          return 1
        fi
      else
        log_info "[WARNING] Infracost analysis failed (check API key or network connection). Skipping cost validation."
      fi
      rm -f "$cost_output_tmp"
      log_info "[SUCCESS] FinOps cost validation passed."
    fi
  fi
}

# 12. Skill-Specific Delegated Checks (auto-discovered)
# 범용성 유지를 위해 플러그인 폴더(bin/hooks/plugins/*.sh) 내 검증 스크립트를 동적 로드
run_delegated_skill_checks() {
  # yaml 변경이 없을 경우 위임 검증 생략 (프로세스 오버헤드 절감)
  if [ "${#GLOBAL_TARGET_YAML_FILES[@]}" -eq 0 ] || [ -z "${GLOBAL_TARGET_YAML_FILES[0]}" ]; then
    return 0
  fi

  # 첫 실패에서 즉시 중단하면 뒤 플러그인은 실행조차 안 된다. 플러그인끼리는 각자
  # git diff --cached를 독립적으로 재조회해 상태를 공유하지 않으므로(k8s-check.sh,
  # observability-check.sh 등) 순서와 무관하게 끝까지 돌려도 안전하다. 같은 파일이
  # 여러 플러그인의 대상이 될 수 있어(예: PrometheusRule YAML은 k8s-check.sh의 PromQL
  # 문법 검사와 observability-check.sh의 알람 정책 검사 양쪽에 다 걸림), 첫 플러그인만
  # 보고하면 두 번째 위반은 재커밋해야 발견된다(2026-08-01 실측). run-suite.sh의
  # 스크립트 간 판정과 동일한 관용구를 여기 플러그인 간에도 적용한다.
  local skill_script rc failed=0
  shopt -s nullglob
  for skill_script in "$PFC_SCRIPT_DIR/plugins"/*.sh; do
    rc=0
    bash "$skill_script" || rc=$?
    [ "$rc" -ne 0 ] && failed=1
  done
  shopt -u nullglob
  [ "$failed" -eq 0 ]
}

# 13. Provenance Logging Reminder (비차단 알림)
# 룰 근거가 필요했는지는 모델의 판단 영역이라 기계적으로 확정할 수 없으므로, 이 검사는
# 절대 커밋을 막지 않는다(항상 return 0). agent-edits-hook.sh가 남긴 더미 라인
# (result: OK/ERROR/FLAGGED)이 아직 record-provenance.sh로 보강(SUCCESS)되지 않은 변경 파일이
# 있으면 목록만 보여준다. "SUCCESS만 보강 완료"라는 기준은 record-provenance.sh 자신의 재진입
# 판정 로직(`$5!="SUCCESS"`, bin/utils/record-provenance.sh 100행)과 동일하게 맞춘 것이다.
check_provenance_reminder() {
  local edits_log="$REPO_ROOT/.agent-state/edits.log"
  [ -f "$edits_log" ] || return 0
  [ "${#GLOBAL_TARGET_FILES[@]}" -eq 0 ] && return 0

  local f last_line last_result unresolved=()
  for f in "${GLOBAL_TARGET_FILES[@]}"; do
    [ -z "$f" ] && continue
    last_line=$(awk -F' \\| ' -v r="$f" '$2==r {line=$0} END{print line}' "$edits_log" 2>/dev/null) || continue
    [ -z "$last_line" ] && continue
    last_result=$(awk -F' \\| ' '{print $5}' <<<"$last_line" 2>/dev/null) || continue
    case "$last_result" in
    SUCCESS) ;;
    *) unresolved+=("$f") ;;
    esac
  done

  if [ "${#unresolved[@]}" -gt 0 ]; then
    log_info "--- Step: Provenance Logging Reminder (Non-blocking) ---"
    echo "[WARNING] 아래 변경 파일은 아직 record-provenance.sh로 근거가 보강되지 않았습니다. 룰 근거가 있는 변경이면 보강하고, 근거 없는 사소한 수정이면 무시하십시오:"
    printf '    %s\n' "${unresolved[@]}"
  fi
  return 0
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
# 확장자만 골라 쓴다(수집-필터링 분리). 예전에는 함수마다 git diff --cached 가 박혀 있어
# 스테이징된 파일 외에는 어떤 방식으로도 검사할 수 없었다.
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
  check_provenance_reminder

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
