#!/usr/bin/env bash
# pre-flight-check.sh - Modular & Fail-safe IaC/Script Validation Pipeline

set -euo pipefail

echo "============================================="
echo "=== Pre-Flight Validation Pipeline Started ==="
echo "============================================="

# -----------------------------------------------------------------------------
# Common Helpers
# -----------------------------------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CACHE_FILE="$REPO_ROOT/.pre-flight-check.cache"

# git commit을 통해 훅으로 실행될 때는 git이 CWD를 항상 저장소 루트로 고정해주지만,
# 사람이나 에이전트가 서브디렉토리에서 이 스크립트를 직접 실행하면 CWD가 그대로 남는다.
# git diff --cached의 '*.sh' 같은 pathspec은 저장소 전체가 아니라 "CWD 기준"으로
# 해석되므로, 서브디렉토리에서 실행할 경우 상위/형제 경로에 스테이징된 변경사항을
# 조용히 못 찾아 검증을 통째로 건너뛰고도 성공으로 보고하는 사고로 이어진다.
cd "$REPO_ROOT" || {
  echo "[ERROR] 저장소 루트($REPO_ROOT)로 이동할 수 없습니다." >&2
  exit 1
}

has_tool() {
  local resolved
  resolved=$(command -v "$1") || return 1
  # mise shim 파일은 command -v로 항상 발견되지만, 해당 도구의 버전이 현재 디렉토리에서
  # 해석되지 않으면(예: mise 설정이 미치지 못하는 위치) 실제 호출 시점에 실패한다.
  # 각 도구마다 다른 --version 플래그를 흉내내는 대신, mise 자체에 해석 가능 여부를 물어본다.
  # 단, PATH에서 찾은 경로가 mise shims 디렉토리 소속일 때만 이 재검증을 수행한다. zsh처럼
  # mise가 애초에 관리하지 않는 시스템 도구(apt 설치)까지 무조건 "mise which"로 되물으면
  # "not a mise bin" 오류로 오탐 처리되어, 실제로는 정상 설치된 도구를 건너뛰게 된다.
  if [[ "$resolved" == "$HOME/.local/share/mise/shims/"* ]] && command -v mise &>/dev/null; then
    mise which "$1" &>/dev/null || return 1
  fi
}

calculate_tf_hash() {
  # main()에서 1회만 판정한 Git 저장소 여부 및 스테이징 .tf 목록을 재사용 (중복 git 호출 제거)
  if [ "$GLOBAL_IS_GIT_REPO" -ne 1 ]; then
    echo "non-git"
    return
  fi

  if [ "${#GLOBAL_STAGED_TF_FILES[@]}" -eq 0 ] || [ -z "${GLOBAL_STAGED_TF_FILES[0]}" ]; then
    echo "empty"
    return
  fi

  # Git Index(스테이징 영역)에 기록된 파일 오브젝트들의 SHA-1 해시 목록을 종합하여 대표 해시 생성
  git ls-files --stage "${GLOBAL_STAGED_TF_FILES[@]}" 2>/dev/null | sha256sum | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# Validation Sub-modules (Isolated Functions)
# -----------------------------------------------------------------------------

# 1. Shell Script Validation
validate_shell() {
  # 스테이징된(Staged) .sh/.zsh 파일만 검사 (validate_terraform과 동일한 패턴).
  # 저장소 전체를 스캔하면 이번 커밋과 무관한 기존 파일의 포맷 문제로도 커밋이
  # 막히므로, 실제로 이번에 add/copy/modify된 파일로 범위를 한정한다.
  # Git 훅 스크립트(pre-commit 등)는 관례상 확장자가 없으므로 */.githooks/* 경로도 함께 포함한다.
  local shell_files=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t shell_files < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.sh' '*.zsh' '*/.githooks/*' 2>/dev/null)
  fi

  if [ "${#shell_files[@]}" -eq 0 ] || [ -z "${shell_files[0]}" ]; then
    echo "--- Step: Shell Script Validation ---"
    echo "[INFO] No staged shell script changes detected. Skipping shell validation."
    return 0
  fi

  echo "--- Step: Shell Script Validation ---"
  # 루프 외부에서 툴 가용성 1회만 확인 (파일마다 command -v 반복 방지)
  local has_shfmt=0 has_zsh=0 has_shellcheck=0
  if has_tool shfmt; then has_shfmt=1; fi
  if has_tool zsh; then has_zsh=1; fi
  if has_tool shellcheck; then has_shellcheck=1; fi

  # shfmt가 존재하면 루프 밖에서 일괄 포맷 체크 (프로세스 오버헤드 절감)
  if [ "$has_shfmt" -eq 1 ]; then
    echo "Checking format for all shell scripts..."
    if ! shfmt -d -i 2 "${shell_files[@]}"; then
      echo "❌ [ERROR] shfmt 포맷이 맞지 않아 커밋이 차단되었습니다. 'shfmt -w -i 2 <파일>'로 정리한 뒤 다시 시도하세요." >&2
      return 1
    fi
  fi

  # zsh 방언은 정적 분석 도구가 지원하지 않으므로 .zsh를 제외한 나머지(.sh, 확장자 없는 훅 파일 등)만 대상으로 삼음
  if [ "$has_shellcheck" -eq 1 ]; then
    local sh_only_files=()
    for f in "${shell_files[@]}"; do
      [[ "$f" != *.zsh ]] && sh_only_files+=("$f")
    done
    if [ "${#sh_only_files[@]}" -gt 0 ]; then
      echo "Running shellcheck..."
      if ! shellcheck "${sh_only_files[@]}"; then
        echo "❌ [ERROR] shellcheck 지적 사항이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
    fi
  else
    echo "[WARNING] shellcheck is not installed. Skipping static analysis for shell scripts."
  fi

  for f in "${shell_files[@]}"; do
    [ -z "$f" ] && continue
    echo "Checking syntax: $f"
    # .zsh 파일은 zsh로, .sh 파일은 bash로 문법 검사
    if [[ "$f" == *.zsh ]]; then
      if [ "$has_zsh" -eq 1 ]; then
        if ! zsh -n "$f"; then
          echo "❌ [ERROR] zsh 문법 오류가 발견되어 커밋이 차단되었습니다: $f" >&2
          return 1
        fi
      else
        echo "[WARNING] zsh not found, skipping syntax check for: $f"
      fi
    else
      if ! bash -n "$f"; then
        echo "❌ [ERROR] bash 문법 오류가 발견되어 커밋이 차단되었습니다: $f" >&2
        return 1
      fi
    fi
  done
  echo "[SUCCESS] Shell scripts validation passed."
}

# 2. Terraform Validation
validate_terraform() {
  # 스테이징된(Staged) .tf 파일만 검사 (validate_shell 등 나머지 검증 함수와 동일한 패턴).
  # 저장소 전체를 스캔하면 이번 커밋과 무관한 기존 .tf 파일 문제로도 커밋이 막히므로,
  # main()에서 1회만 조회한 스테이징 목록을 재사용한다.
  local tf_files=("${GLOBAL_STAGED_TF_FILES[@]}")

  if [ "${#tf_files[@]}" -gt 0 ] && [ -n "${tf_files[0]}" ]; then
    echo "--- Step: Terraform Validation ---"

    # 스테이징 영역 캐시 확인 (수정사항이 없거나 변경점이 일치하면 즉시 스킵)
    if [ "$GLOBAL_TF_HASH" = "empty" ]; then
      echo "[INFO] No staged Terraform changes detected. Skipping Terraform validation (Cache hit - empty)."
      return 0
    elif [ -f "$CACHE_FILE" ] && [ "$GLOBAL_TF_HASH" != "non-git" ] && [ "$GLOBAL_TF_HASH" == "$(cat "$CACHE_FILE" 2>/dev/null)" ]; then
      echo "[INFO] Staged Terraform configuration is unchanged. Skipping Terraform validation (Cache hit)."
      return 0
    fi
    if ! has_tool terraform; then
      echo "[ERROR] terraform CLI is required but not installed." >&2
      return 1
    fi

    echo "Running terraform fmt check..."
    if ! terraform fmt -check -recursive; then
      echo "❌ [ERROR] terraform fmt 포맷이 맞지 않아 커밋이 차단되었습니다. 'terraform fmt -recursive'로 정리한 뒤 다시 시도하세요." >&2
      return 1
    fi

    echo "Running terraform validate (offline initialization)..."
    if [ ! -d ".terraform" ]; then
      if ! terraform init -backend=false -input=false >/dev/null; then
        echo "❌ [ERROR] terraform init 초기화에 실패하여 커밋이 차단되었습니다." >&2
        return 1
      fi
    fi
    if ! terraform validate; then
      echo "❌ [ERROR] terraform validate 검증에 실패하여 커밋이 차단되었습니다." >&2
      return 1
    fi

    if has_tool tflint; then
      echo "Running tflint..."
      if [ -f ".tflint.hcl" ]; then
        tflint --init || true
      fi
      if ! tflint; then
        echo "❌ [ERROR] tflint 정적 분석에서 지적 사항이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
    else
      echo "[WARNING] tflint is not installed. Skipping static analysis."
    fi

    if has_tool checkov; then
      # tflint는 문법/베스트프랙티스 위주라 과도한 IAM 권한, 퍼블릭 S3, 미암호화 리소스 같은
      # "보안 오구성"은 잡지 못한다. checkov가 이 역할을 보완한다. LOW/MEDIUM은 soft-fail로
      # 완화해 알림만 남기고, HIGH/CRITICAL만 커밋을 차단하도록 제한한다.
      echo "Running checkov (Terraform security misconfiguration scan)..."
      if ! checkov --directory . --framework terraform --compact --quiet --soft-fail-on LOW,MEDIUM; then
        echo "❌ [ERROR] checkov에서 HIGH/CRITICAL 등급의 보안 오구성이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
    else
      echo "[WARNING] checkov is not installed. Skipping IaC security misconfiguration scan."
    fi
    echo "[SUCCESS] Terraform validation passed."
  fi
}

# 3. AWS SAM Validation
validate_sam() {
  # [ -f "template.yaml" ]처럼 저장소 루트만 보면, SAM 템플릿이 흔히 그러듯 서브디렉토리에
  # 있는 경우 검증이 통째로 무력화된다. 다른 검증 함수와 동일하게 스테이징된 파일 목록을
  # git pathspec으로 조회해 위치에 무관하게 찾는다.
  local sam_templates=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t sam_templates < <(git diff --cached --name-only -z --diff-filter=ACM -- '*template.yaml' '*template.yml' 2>/dev/null)
  fi

  if [ "${#sam_templates[@]}" -eq 0 ] || [ -z "${sam_templates[0]}" ]; then
    return 0
  fi

  if ! has_tool sam; then
    echo "--- Step: AWS SAM Validation ---"
    echo "[WARNING] SAM templates found but sam CLI is not installed."
    return 0
  fi

  echo "--- Step: AWS SAM Validation ---"
  for tpl in "${sam_templates[@]}"; do
    [ -z "$tpl" ] && continue
    echo "Validating SAM template: $tpl"
    if ! sam validate --template-file "$tpl"; then
      echo "❌ [ERROR] SAM 템플릿 검증에 실패하여 커밋이 차단되었습니다: $tpl" >&2
      return 1
    fi
  done
  echo "[SUCCESS] SAM template validation passed."
}

# 4. Azure Bicep Validation
validate_bicep() {
  local bicep_files=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t bicep_files < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.bicep' 2>/dev/null)
  fi

  if [ "${#bicep_files[@]}" -eq 0 ] || [ -z "${bicep_files[0]}" ]; then
    return 0
  fi

  # Bicep(.NET 기반)이 libicu가 없는 Linux 환경에서도 정상 실행되도록 Invariant 모드 강제 활성화
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

  if ! has_tool bicep && ! { has_tool az && az bicep version &>/dev/null; }; then
    echo "--- Step: Azure Bicep Validation ---"
    echo "[WARNING] Bicep files found but neither standalone 'bicep' CLI nor 'az bicep' is installed."
    return 0
  fi

  echo "--- Step: Azure Bicep Validation ---"
  local bicep_cmd="none"
  if has_tool bicep && bicep --version &>/dev/null; then
    bicep_cmd="standalone"
  elif has_tool az && az bicep version &>/dev/null; then
    bicep_cmd="az"
  fi

  for bf in "${bicep_files[@]}"; do
    [ -z "$bf" ] && continue
    echo "Validating bicep file: $bf"

    if [ "$bicep_cmd" = "standalone" ]; then
      if ! bicep build "$bf" --stdout >/dev/null; then
        echo "❌ [ERROR] Bicep 템플릿 검증에 실패하여 커밋이 차단되었습니다: $bf" >&2
        return 1
      fi
    elif [ "$bicep_cmd" = "az" ]; then
      if ! az bicep build --file "$bf" --stdout >/dev/null; then
        echo "❌ [ERROR] Bicep 템플릿 검증에 실패하여 커밋이 차단되었습니다: $bf" >&2
        return 1
      fi
    else
      echo "❌ [ERROR] Bicep 실행 파일을 찾을 수 없거나 실행이 불가능합니다(OS 호환성 문제 등). 커밋이 차단되었습니다." >&2
      return 1
    fi
  done
  echo "[SUCCESS] Bicep validation passed."
}

# 4. Ansible Validation
validate_ansible() {
  # 글롭 없는 'site.yml'/'roles' pathspec은 저장소 루트에 있는 경우만 매칭된다. 실제로는
  # ansible/site.yml, ansible/roles/... 처럼 서브디렉토리에 두는 구성이 흔하므로, 다른
  # 검증 함수와 동일하게 글롭을 붙여 위치에 무관하게 찾는다.
  local ansible_files=() staged_roles=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t ansible_files < <(git diff --cached --name-only -z --diff-filter=ACM -- '*playbook*.yml' '*playbook*.yaml' '*site.yml' '*site.yaml' 2>/dev/null)
    mapfile -d '' -t staged_roles < <(git diff --cached --name-only -z --diff-filter=ACM -- '*roles/*' 2>/dev/null)
  fi

  if { [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ]; } || { [ "${#staged_roles[@]}" -gt 0 ] && [ -n "${staged_roles[0]}" ]; }; then
    echo "--- Step: Ansible Validation ---"
    if has_tool ansible-playbook && [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ]; then
      for pf in "${ansible_files[@]}"; do
        [ -z "$pf" ] && continue
        echo "Checking ansible syntax: $pf"
        if ! ansible-playbook --syntax-check "$pf"; then
          echo "❌ [ERROR] Ansible 플레이북 문법 검사에 실패하여 커밋이 차단되었습니다: $pf" >&2
          return 1
        fi
      done
    fi
    if has_tool ansible-lint; then
      echo "Running ansible-lint..."
      if ! ansible-lint; then
        echo "❌ [ERROR] ansible-lint 지적 사항이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
      echo "[SUCCESS] Ansible validation passed."
    else
      echo "[WARNING] ansible-lint is not installed. Skipping lint validation."
    fi
  fi
}

# 5. K8s Helm Validation
validate_helm() {
  # [ -f "Chart.yaml" ] + 정확히 'Chart.yaml'/'values.yaml'/'templates'라는 이름의 pathspec은
  # 둘 다 저장소 루트만 본다. 실무에서는 차트가 거의 항상 서브디렉토리(charts/foo 등)에
  # 있으므로, 이 게이트로는 Helm 차트가 있는 대부분의 저장소에서 검증이 통째로
  # 무력화된다. 글롭 pathspec으로 위치에 무관하게 스테이징된 차트 관련 변경을 찾는다.
  local helm_changed=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t helm_changed < <(git diff --cached --name-only -z --diff-filter=ACM -- '*Chart.yaml' '*values.yaml' '*/templates/*' 2>/dev/null)
  fi
  if [ "${#helm_changed[@]}" -eq 0 ] || [ -z "${helm_changed[0]}" ]; then
    return 0
  fi

  if ! has_tool helm; then
    echo "--- Step: Helm Chart Validation ---"
    echo "[WARNING] Chart.yaml found but helm CLI is not installed."
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

  echo "--- Step: Helm Chart Validation ---"
  for d in "${chart_dirs[@]}"; do
    echo "Linting chart: $d"
    if ! helm lint "$d"; then
      echo "❌ [ERROR] Helm lint 지적 사항이 발견되어 커밋이 차단되었습니다: $d" >&2
      return 1
    fi
  done
  echo "[SUCCESS] Helm lint passed."
}

# 6. Raw K8s Manifest Validation
validate_k8s_manifests() {
  # main()에서 1회만 조회한 스테이징 YAML 목록을 재사용 (validate_yaml과 중복 git diff 호출 방지)
  local staged_yaml=("${GLOBAL_STAGED_YAML_FILES[@]}")

  # Helm 차트의 templates/ 하위는 Go 템플릿 구문이 섞인 파일이라 순수 YAML 파서(kubectl/kube-linter)로 검증 불가 (validate_helm에서 helm lint로 별도 검증됨)
  local k8s_manifests=()
  for f in "${staged_yaml[@]}"; do
    [ -z "$f" ] && continue
    [[ "$f" == */templates/* ]] && continue
    [ -f "$f" ] || continue
    grep -qE "^kind:" "$f" 2>/dev/null && k8s_manifests+=("$f")
  done

  if [ "${#k8s_manifests[@]}" -gt 0 ] && [ -n "${k8s_manifests[0]}" ]; then
    echo "--- Step: K8s Manifest Validation ---"
    if has_tool kube-linter; then
      echo "Running kube-linter for all manifests..."
      if ! kube-linter lint "${k8s_manifests[@]}"; then
        echo "❌ [ERROR] kube-linter 지적 사항이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
      echo "[SUCCESS] kube-linter passed."
    elif has_tool kubectl; then
      echo "Running kubectl --dry-run (client-side) for manifest validation..."
      for mf in "${k8s_manifests[@]}"; do
        [ -z "$mf" ] && continue
        echo "Validating: $mf"
        if ! kubectl apply --dry-run=client -f "$mf" 2>&1; then
          echo "❌ [ERROR] kubectl dry-run 검증에 실패하여 커밋이 차단되었습니다: $mf" >&2
          return 1
        fi
      done
      echo "[SUCCESS] kubectl dry-run validation passed."
    else
      echo "[WARNING] K8s manifests found but neither kube-linter nor kubectl is installed."
    fi
  fi
}

# 7. Dockerfile Validation
validate_docker() {
  local dockerfiles=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t dockerfiles < <(git diff --cached --name-only -z --diff-filter=ACM -- '*Dockerfile*' 2>/dev/null)
  fi

  if [ "${#dockerfiles[@]}" -gt 0 ] && [ -n "${dockerfiles[0]}" ]; then
    if has_tool hadolint; then
      echo "--- Step: Dockerfile Validation ---"
      echo "Linting Dockerfiles..."
      if ! hadolint "${dockerfiles[@]}"; then
        echo "❌ [ERROR] hadolint 지적 사항이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
      echo "[SUCCESS] Dockerfile validation passed."
    else
      echo "[WARNING] Dockerfiles found but hadolint is not installed."
    fi

    # syft/grype는 본래 "빌드된 이미지"를 대상으로 하는 도구다. 커밋마다 docker build를 돌려
    # 이미지를 스캔하면 베이스 이미지 pull과 빌드 시간 때문에 수 분까지 걸릴 수 있어 이 파이프라인의
    # 속도 목표(0.5초대)와 정면 충돌한다. 대신 `dir:.` 소스 스캔으로 전환해, Dockerfile과 함께
    # 저장소에 있는 requirements.txt/package.json/go.mod 등 의존성 매니페스트에 이미 알려진 취약
    # 버전이 박혀있는지를 빌드 없이 확인한다. (이미지 레이어 자체의 취약점/서명은 여기서 잡히지
    # 않으므로, 실제 배포 전에는 containers 스킬의 030-supply-chain-security-standard.md가 요구하는
    # 이미지 단계 스캔·서명이 별도로 필요하다.) Trivy의 vuln/misconfig 스캔과 동일하게 경고만
    # 남기고 커밋을 막지는 않는다 — 베이스 이미지의 기존 CVE로 매 커밋이 막히는 것을 피하기 위함.
    echo "--- Step: Container Supply Chain Scan (SBOM/Vuln, Source-level) ---"
    if has_tool syft; then
      echo "[INFO] Generating source SBOM (syft)..."
      syft dir:. -o table || echo "[WARNING] syft SBOM 생성에 실패했습니다."
    else
      echo "[WARNING] syft is not installed. Skipping SBOM generation."
    fi

    if has_tool grype; then
      echo "[INFO] Scanning dependency manifests for known CRITICAL vulnerabilities (grype, warning-only)..."
      if ! grype dir:. --fail-on critical; then
        echo "[WARNING] grype 스캔에서 CRITICAL 취약점이 발견되었습니다. 이미지 빌드 전 의존성 버전을 확인하십시오."
      fi
    else
      echo "[WARNING] grype is not installed. Skipping dependency vulnerability scan."
    fi
  fi
}

# 8. YAML Style & Validation (Relaxed / Fail-safe)
validate_yaml() {
  # main()에서 1회만 조회한 스테이징 YAML 목록을 재사용 (validate_k8s_manifests와 중복 git diff 호출 방지)
  local staged_yaml=("${GLOBAL_STAGED_YAML_FILES[@]}")

  # Helm 차트의 templates/ 하위는 Go 템플릿 구문이 섞여 있어 순수 YAML 린터(yamllint) 검증 대상에서 제외
  local yaml_files=()
  for f in "${staged_yaml[@]}"; do
    [ -z "$f" ] && continue
    [[ "$f" == */templates/* ]] && continue
    yaml_files+=("$f")
  done

  if [ "${#yaml_files[@]}" -gt 0 ] && [ -n "${yaml_files[0]}" ]; then
    if has_tool yamllint; then
      echo "--- Step: YAML Style Validation (Relaxed) ---"
      # find로 필터링된 모든 YAML 파일을 일괄 검사
      if ! yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${yaml_files[@]}"; then
        echo "❌ [ERROR] yamllint 지적 사항이 발견되어 커밋이 차단되었습니다." >&2
        return 1
      fi
      echo "[SUCCESS] YAML format validation passed."
    else
      echo "[WARNING] YAML files found but yamllint is not installed."
    fi
  fi
}

# 9. OPA/Conftest Policy Validation
validate_conftest() {
  local staged_rego=() staged_config=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t staged_rego < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.rego' 2>/dev/null)
    mapfile -d '' -t staged_config < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.yaml' '*.yml' '*.json' 2>/dev/null)
  fi

  local has_staged_rego=0 has_staged_config=0
  { [ "${#staged_rego[@]}" -gt 0 ] && [ -n "${staged_rego[0]}" ]; } && has_staged_rego=1
  { [ "${#staged_config[@]}" -gt 0 ] && [ -n "${staged_config[0]}" ]; } && has_staged_config=1

  # [ -d "policy" ]는 저장소 루트만 보므로 infra/policy/ 처럼 서브디렉토리에 정책을 두는
  # 흔한 구성에서는 "이 저장소가 conftest를 쓰는지" 판정 자체가 실패한다. 위치에 무관하게
  # 추적 중인 .rego 파일이 하나라도 있는지로 대체한다.
  local has_any_rego=0
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ] && [ -n "$(git ls-files -- '*.rego' 2>/dev/null)" ]; then
    has_any_rego=1
  fi

  if [ "$has_staged_rego" -eq 1 ] || { [ "$has_any_rego" -eq 1 ] && [ "$has_staged_config" -eq 1 ]; }; then
    if has_tool conftest; then
      echo "--- Step: Conftest Policy Validation ---"

      # conftest는 --policy를 안 주면 기본적으로 CWD 기준 ./policy 디렉토리만 찾는다.
      # infra/policy/ 처럼 다른 위치에 정책이 있으면 "stat policy: no such file or
      # directory"로 실패하므로, 추적 중인 .rego 파일들이 실제로 위치한 디렉토리를
      # 모아 --policy로 명시한다.
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
        # 정책(.rego) 자체가 바뀐 경우: 기존에 이미 존재하던 설정 파일들이 새 정책도
        # 여전히 통과하는지 확인해야 하므로 저장소 전체를 대상으로 검사한다.
        echo "[INFO] Rego policy changed. Testing against the entire repository for regressions."
        if ! conftest test "${policy_flags[@]}" .; then
          echo "❌ [ERROR] Conftest 정책 위반이 발견되어 커밋이 차단되었습니다." >&2
          return 1
        fi
      else
        # 정책은 그대로이고 설정 파일만 바뀐 경우: 이번에 변경된 파일만 검사해도
        # (다른 설정 파일은 이미 기존 정책을 통과한 상태이므로) 무관한 재검사를 피할 수 있다.
        if ! conftest test "${policy_flags[@]}" "${staged_config[@]}"; then
          echo "❌ [ERROR] Conftest 정책 위반이 발견되어 커밋이 차단되었습니다." >&2
          return 1
        fi
      fi
      echo "[SUCCESS] Conftest validation passed."
    else
      echo "[WARNING] Rego policies found but conftest is not installed."
    fi
  fi
}

# 10. Security & Secret Scan
validate_security() {
  echo "--- Step: Security and Secret Scan ---"
  if has_tool trivy; then
    echo "Running trivy fs scan..."

    # 24시간(86400초) 수명 주기 정책 설정
    local db_ttl=86400
    local timestamp_file="$REPO_ROOT/.trivy-db-update.timestamp"
    local skip_flags=()

    local now
    now=$(date +%s)

    if [ -f "$timestamp_file" ]; then
      local last_update
      last_update=$(cat "$timestamp_file" 2>/dev/null || echo 0)
      # 디스크 쓰기 중단 등으로 타임스탬프 파일이 숫자가 아닌 값으로 손상된 경우, 그 값을
      # 그대로 산술 연산에 넣으면 bash가 변수명으로 오인 시도하다 "unbound variable" 같은
      # 알아보기 힘든 에러로 죽는다. 숫자가 아니면 캐시가 없는 것처럼 안전하게 폴백한다.
      if ! [[ "$last_update" =~ ^[0-9]+$ ]]; then
        last_update=0
      fi
      local age=$((now - last_update))

      # 캐시 수명이 아직 유효한 경우 업데이트 스킵 플래그 동적 주입
      if [ "$age" -lt "$db_ttl" ]; then
        echo "[INFO] Trivy DB cache is still valid ($((age / 3600))h old). Skipping DB update."
        skip_flags=(--skip-db-update --skip-check-update)
      fi
    fi

    # 1. 시크릿(비밀키, 토큰 등) 검사는 강제 차단 (exit-code 1)
    if ! trivy fs "${skip_flags[@]}" --scanners secret --exit-code 1 .; then
      echo "❌ [ERROR] 시크릿(비밀키/토큰) 유출이 감지되어 커밋이 차단되었습니다."
      return 1
    fi
    echo "[SUCCESS] Trivy secret scan passed."

    # 2. 보안 취약점 및 설정 오류(vuln, misconfig)는 발견되어도 커밋을 막지 않지만(exit-code 0),
    #    스캔 자체의 실행 실패(네트워크 오류 등)는 구분하여 "성공"으로 오보되지 않도록 한다.
    echo "[INFO] Running trivy vulnerability & misconfig scan (Warnings only)..."
    if trivy fs "${skip_flags[@]}" --severity HIGH,CRITICAL --scanners vuln,misconfig --exit-code 0 .; then
      echo "[SUCCESS] Trivy vuln/misconfig scan passed."
    else
      echo "[WARNING] Trivy vuln/misconfig scan failed to run (see output above). Continuing without blocking the commit."
    fi

    # 실제 업데이트를 진행한 경우에만 타임스탬프 최신화
    if [ "${#skip_flags[@]}" -eq 0 ]; then
      echo "$now" >"$timestamp_file" 2>/dev/null
    fi
  elif has_tool trufflehog; then
    echo "Running trufflehog filesystem scan..."
    if ! trufflehog filesystem --no-update --fail .; then
      echo "❌ [ERROR] 시크릿(비밀키/토큰) 유출이 감지되어 커밋이 차단되었습니다."
      return 1
    fi
    echo "[SUCCESS] Trufflehog secret scan passed."
  else
    echo "[WARNING] Neither trivy nor trufflehog is installed. Skipping security scanning."
  fi
}

# 11. FinOps Cost Validation (Infracost)
validate_finops_costs() {
  # 커밋 시점이 아닐 경우 비용 검사 생략 (API 호출 제한 절약)
  if [ "${RUN_COST_CHECK:-false}" != "true" ]; then
    echo "--- Step: FinOps Cost Validation (Infracost) ---"
    echo "[INFO] Not in Git commit stage. Skipping cost validation to save API limits."
    return 0
  fi

  # main()에서 1회만 조회한 스테이징 .tf 목록을 재사용 (validate_terraform과 동일한 패턴)
  local tf_files=("${GLOBAL_STAGED_TF_FILES[@]}")

  if [ "${#tf_files[@]}" -gt 0 ] && [ -n "${tf_files[0]}" ]; then
    # 스테이징 영역 캐시 확인 (수정사항이 없거나 변경점이 일치하면 즉시 스킵)
    if [ "$GLOBAL_TF_HASH" = "empty" ]; then
      echo "--- Step: FinOps Cost Validation (Infracost) ---"
      echo "[INFO] No staged Terraform changes detected. Skipping cost validation (Cache hit - empty)."
      return 0
    elif [ -f "$CACHE_FILE" ] && [ "$GLOBAL_TF_HASH" != "non-git" ] && [ "$GLOBAL_TF_HASH" == "$(cat "$CACHE_FILE" 2>/dev/null)" ]; then
      echo "--- Step: FinOps Cost Validation (Infracost) ---"
      echo "[INFO] Staged Terraform configuration is unchanged. Skipping cost validation (Cache hit)."
      return 0
    fi
    if has_tool infracost; then
      echo "--- Step: FinOps Cost Validation (Infracost) ---"
      echo "Checking for AWS/Azure Extended Support & LTS pricing..."

      local cost_output_tmp
      cost_output_tmp=$(mktemp)
      # infracost breakdown 실행 도중 인터럽트(Ctrl-C 등)되어 아래 rm -f들이
      # 실행되지 못하는 경우에 대비해 스크립트 종료 시 임시파일 정리를 보장한다.
      # trap은 함수 반환 후(local 변수가 스코프를 벗어난 뒤) 스크립트 종료 시점에
      # 실행될 수 있으므로, set -u 하에서 unbound variable 에러가 나지 않도록
      # ${cost_output_tmp:-}로 안전하게 참조한다.
      trap 'rm -f "${cost_output_tmp:-}"' EXIT

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
        echo "[WARNING] Infracost analysis failed (check API key or network connection). Skipping cost validation."
      fi
      rm -f "$cost_output_tmp"
      echo "[SUCCESS] FinOps cost validation passed."
    fi
  fi
}

# 12. Skill-Specific Delegated Checks (auto-discovered)
# 특정 스킬(k8s 등)에만 필요한 도구(kyverno, promtool, yq, pluto 등)를 이 범용
# 스크립트에 직접 넣으면 그 스킬과 무관한 프로젝트까지 의존성이 늘어난다. 대신 각
# 스킬 폴더의 전용 검증 스크립트(*-check.sh 네이밍 컨벤션)를 자동으로 찾아 호출한다.
# 나중에 aws-check.sh, azure-check.sh 등이 추가되어도 이 파일을 다시 고칠 필요가 없다.
run_delegated_skill_checks() {
  # 스테이징된 yaml이 하나도 없으면 스킬별 스크립트를 띄울 필요조차 없다 (지금까지
  # 존재하는 스킬 스크립트의 대상 파일은 전부 yaml이므로 이 필터로 놓치는 케이스는 없다).
  # k8s 등과 무관한 프로젝트(순수 Terraform 등)에서 매번 서브프로세스가 뜨는 낭비를 막는다.
  if [ "${#GLOBAL_STAGED_YAML_FILES[@]}" -eq 0 ] || [ -z "${GLOBAL_STAGED_YAML_FILES[0]}" ]; then
    return 0
  fi

  # 이 스크립트 자신(심볼릭 링크로 호출된 경우 포함)을 실제 경로로 해석해두고,
  # glob 결과에서 스스로를 걸러내 무한 재귀 호출을 방지한다.
  local self_path
  self_path=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)

  local skill_script resolved
  shopt -s nullglob
  for skill_script in "$HOME"/dotfiles/contexts/*/scripts/*-check.sh; do
    resolved=$(readlink -f "$skill_script" 2>/dev/null)
    [ "$resolved" = "$self_path" ] && continue
    if ! bash "$skill_script"; then
      shopt -u nullglob
      return 1
    fi
  done
  shopt -u nullglob
}

# -----------------------------------------------------------------------------
# Main Orchestration Flow
# -----------------------------------------------------------------------------
# 전역 캐시 변수 선언 (쉘 연산 호출 중복 제거)
GLOBAL_IS_GIT_REPO=0
GLOBAL_TF_HASH=""
GLOBAL_STAGED_TF_FILES=()
GLOBAL_STAGED_YAML_FILES=()

main() {
  # Git 저장소 여부 및 여러 검증 함수(shell/ansible/helm/docker/conftest,
  # terraform/finops, yaml/k8s-manifest)가 공유하는 스테이징 파일 목록을 여기서 1회만
  # 조회하여, 함수마다 반복되던 git rev-parse/git diff 호출을 제거한다.
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    GLOBAL_IS_GIT_REPO=1
    mapfile -d '' -t GLOBAL_STAGED_TF_FILES < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.tf' 2>/dev/null)
    mapfile -d '' -t GLOBAL_STAGED_YAML_FILES < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.yaml' '*.yml' 2>/dev/null)
  fi

  # calculate_tf_hash는 위에서 채운 GLOBAL_IS_GIT_REPO/GLOBAL_STAGED_TF_FILES를 재사용한다.
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

  # 검증 성공 시 스테이징 캐시 갱신 (변경 대상이 있을 때만 업데이트)
  if [ "$GLOBAL_TF_HASH" != "empty" ] && [ "$GLOBAL_TF_HASH" != "non-git" ]; then
    echo "$GLOBAL_TF_HASH" >"$CACHE_FILE" 2>/dev/null
  fi

  echo "================================================="
  echo "=== All Pre-Flight Checks Passed Successfully ==="
  echo "================================================="
}

# Run execution
main
