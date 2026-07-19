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

has_tool() {
  command -v "$1" &> /dev/null || return 1
}

calculate_tf_hash() {
  # Git 저장소 여부 확인
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "non-git"
    return
  fi

  # 스테이징된(Staged) .tf 파일 목록 조회 (공백 포함 안전 처리를 위해 NUL 구분 배열 사용)
  local staged_tf=()
  mapfile -d '' -t staged_tf < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.tf' 2>/dev/null)

  if [ "${#staged_tf[@]}" -eq 0 ] || [ -z "${staged_tf[0]}" ]; then
    echo "empty"
    return
  fi

  # Git Index(스테이징 영역)에 기록된 파일 오브젝트들의 SHA-1 해시 목록을 종합하여 대표 해시 생성
  git ls-files --stage "${staged_tf[@]}" 2>/dev/null | sha256sum | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# Validation Sub-modules (Isolated Functions)
# -----------------------------------------------------------------------------

# 1. Shell Script Validation
validate_shell() {
  local shell_files=()
  while IFS= read -r -d '' file; do
    shell_files+=("$file")
  done < <(find . -maxdepth 3 \( -name ".*" -o -name "contexts" \) -prune -o \( -name "*.sh" -o -name "*.zsh" \) -print0 2>/dev/null)

  if [ "${#shell_files[@]}" -gt 0 ] && [ -n "${shell_files[0]}" ]; then
    echo "--- Step: Shell Script Validation ---"
    # 루프 외부에서 툴 가용성 1회만 확인 (파일마다 command -v 반복 방지)
    local has_shfmt=0 has_zsh=0
    if has_tool shfmt; then has_shfmt=1; fi
    if has_tool zsh; then has_zsh=1; fi

    # shfmt가 존재하면 루프 밖에서 일괄 포맷 체크 (프로세스 오버헤드 절감)
    if [ "$has_shfmt" -eq 1 ]; then
      echo "Checking format for all shell scripts..."
      shfmt -d "${shell_files[@]}"
    fi

    for f in "${shell_files[@]}"; do
      [ -z "$f" ] && continue
      echo "Checking syntax: $f"
      # .zsh 파일은 zsh로, .sh 파일은 bash로 문법 검사
      if [[ "$f" == *.zsh ]]; then
        if [ "$has_zsh" -eq 1 ]; then
          zsh -n "$f"
        else
          echo "[WARNING] zsh not found, skipping syntax check for: $f"
        fi
      else
        bash -n "$f"
      fi
    done
    echo "[SUCCESS] Shell scripts validation passed."
  fi
}

# 2. Terraform Validation
validate_terraform() {
  local tf_files=()
  while IFS= read -r -d '' file; do
    tf_files+=("$file")
  done < <(find . -maxdepth 3 -name ".*" -prune -o -name "*.tf" -print0 2>/dev/null)

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
    terraform fmt -check -recursive

    echo "Running terraform validate (offline initialization)..."
    if [ ! -d ".terraform" ]; then
      terraform init -backend=false -input=false > /dev/null
    fi
    terraform validate

    if has_tool tflint; then
      echo "Running tflint..."
      if [ -f ".tflint.hcl" ]; then
        tflint --init || true
      fi
      tflint
    else
      echo "[WARNING] tflint is not installed. Skipping static analysis."
    fi
    echo "[SUCCESS] Terraform validation passed."
  fi
}

# 3. AWS SAM Validation
validate_sam() {
  if [ -f "template.yaml" ] || [ -f "template.yml" ]; then
    if has_tool sam; then
      echo "--- Step: AWS SAM Validation ---"
      sam validate
      echo "[SUCCESS] SAM template validation passed."
    else
      echo "[WARNING] SAM templates found but sam CLI is not installed."
    fi
  fi
}

# 4. Azure Bicep Validation
validate_bicep() {
  local bicep_files=()
  while IFS= read -r -d '' file; do
    bicep_files+=("$file")
  done < <(find . -maxdepth 3 -name ".*" -prune -o -name "*.bicep" -print0 2>/dev/null)

  if [ "${#bicep_files[@]}" -gt 0 ] && [ -n "${bicep_files[0]}" ]; then
    if has_tool az && az bicep version &>/dev/null; then
      echo "--- Step: Azure Bicep Validation ---"
      for bf in "${bicep_files[@]}"; do
        [ -z "$bf" ] && continue
        echo "Validating bicep file: $bf"
        az bicep build --file "$bf" --stdout &>/dev/null
      done
      echo "[SUCCESS] Bicep validation passed."
    else
      echo "[WARNING] Bicep files found but az CLI with bicep extension is not installed."
    fi
  fi
}

# 5. Ansible Validation
validate_ansible() {
  local ansible_files=()
  while IFS= read -r -d '' file; do
    ansible_files+=("$file")
  done < <(find . -maxdepth 2 -name ".*" -prune -o \( -name "*playbook*.yml" -o -name "*playbook*.yaml" -o -name "site.yml" -o -name "site.yaml" \) -print0 2>/dev/null)

  if [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ] || [ -d "roles" ]; then
    echo "--- Step: Ansible Validation ---"
    if has_tool ansible-playbook && [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ]; then
      for pf in "${ansible_files[@]}"; do
        [ -z "$pf" ] && continue
        echo "Checking ansible syntax: $pf"
        ansible-playbook --syntax-check "$pf"
      done
    fi
    if has_tool ansible-lint; then
      echo "Running ansible-lint..."
      ansible-lint
    else
      echo "[WARNING] ansible-lint is not installed."
    fi
    echo "[SUCCESS] Ansible validation passed."
  fi
}

# 6. K8s Helm Validation
validate_helm() {
  if [ -f "Chart.yaml" ]; then
    echo "--- Step: Helm Chart Validation ---"
    if has_tool helm; then
      helm lint .
      echo "[SUCCESS] Helm lint passed."
    else
      echo "[WARNING] Chart.yaml found but helm CLI is not installed."
    fi
  fi
}

# 7. Raw K8s Manifest Validation
validate_k8s_manifests() {
  local k8s_manifests=()
  # Helm 차트의 templates/ 하위는 Go 템플릿 구문이 섞인 파일이라 순수 YAML 파서(kubectl/kube-linter)로 검증 불가 (validate_helm에서 helm lint로 별도 검증됨)
  while IFS= read -r -d '' file; do
    k8s_manifests+=("$file")
  done < <(find . -maxdepth 4 \( -name ".*" -o -name "contexts" -o -name "templates" \) -prune -o \( -name "*.yaml" -o -name "*.yml" \) -exec grep -qE "^kind:" {} \; -print0 2>/dev/null)

  if [ "${#k8s_manifests[@]}" -gt 0 ] && [ -n "${k8s_manifests[0]}" ]; then
    echo "--- Step: K8s Manifest Validation ---"
    if has_tool kube-linter; then
      echo "Running kube-linter for all manifests..."
      kube-linter lint "${k8s_manifests[@]}"
      echo "[SUCCESS] kube-linter passed."
    elif has_tool kubectl; then
      echo "Running kubectl --dry-run (client-side) for manifest validation..."
      for mf in "${k8s_manifests[@]}"; do
        [ -z "$mf" ] && continue
        echo "Validating: $mf"
        kubectl apply --dry-run=client -f "$mf" 2>&1
      done
      echo "[SUCCESS] kubectl dry-run validation passed."
    else
      echo "[WARNING] K8s manifests found but neither kube-linter nor kubectl is installed."
    fi
  fi
}

# 8. Dockerfile Validation
validate_docker() {
  local dockerfiles=()
  while IFS= read -r -d '' file; do
    dockerfiles+=("$file")
  done < <(find . -maxdepth 3 -name ".*" -prune -o \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "Dockerfile-*" \) -print0 2>/dev/null)

  if [ "${#dockerfiles[@]}" -gt 0 ] && [ -n "${dockerfiles[0]}" ]; then
    if has_tool hadolint; then
      echo "--- Step: Dockerfile Validation ---"
      echo "Linting Dockerfiles..."
      hadolint "${dockerfiles[@]}"
      echo "[SUCCESS] Dockerfile validation passed."
    else
      echo "[WARNING] Dockerfiles found but hadolint is not installed."
    fi
  fi
}

# 9. YAML Style & Validation (Relaxed / Fail-safe)
validate_yaml() {
  local yaml_files=()
  # Helm 차트의 templates/ 하위는 Go 템플릿 구문이 섞여 있어 순수 YAML 린터(yamllint) 검증 대상에서 제외
  while IFS= read -r -d '' file; do
    yaml_files+=("$file")
  done < <(find . -maxdepth 4 \( -name ".*" -o -name "contexts" -o -name "templates" \) -prune -o \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

  if [ "${#yaml_files[@]}" -gt 0 ] && [ -n "${yaml_files[0]}" ]; then
    if has_tool yamllint; then
      echo "--- Step: YAML Style Validation (Relaxed) ---"
      # find로 필터링된 모든 YAML 파일을 일괄 검사
      yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${yaml_files[@]}"
      echo "[SUCCESS] YAML format validation passed."
    else
      echo "[WARNING] YAML files found but yamllint is not installed."
    fi
  fi
}

# 10. OPA/Conftest Policy Validation
validate_conftest() {
  local rego_files=()
  while IFS= read -r -d '' file; do
    rego_files+=("$file")
  done < <(find . -maxdepth 3 -name ".*" -prune -o -name "*.rego" -print0 2>/dev/null)

  if [ "${#rego_files[@]}" -gt 0 ] && [ -n "${rego_files[0]}" ] || [ -d "policy" ]; then
    if has_tool conftest; then
      echo "--- Step: Conftest Policy Validation ---"
      conftest test .
      echo "[SUCCESS] Conftest validation passed."
    else
      echo "[WARNING] Rego policies found but conftest is not installed."
    fi
  fi
}

# 11. Security & Secret Scan
validate_security() {
  echo "--- Step: Security and Secret Scan ---"
  if has_tool trivy; then
    echo "Running trivy fs scan..."
    
    # 24시간(86400초) 수명 주기 정책 설정
    local db_ttl=86400
    local timestamp_file="$REPO_ROOT/.trivy-db-update.timestamp"
    local skip_flags=""
    
    local now
    now=$(date +%s)
    
    if [ -f "$timestamp_file" ]; then
      local last_update
      last_update=$(cat "$timestamp_file" 2>/dev/null || echo 0)
      local age=$((now - last_update))
      
      # 캐시 수명이 아직 유효한 경우 업데이트 스킵 플래그 동적 주입
      if [ "$age" -lt "$db_ttl" ]; then
        echo "[INFO] Trivy DB cache is still valid ($((age / 3600))h old). Skipping DB update."
        skip_flags="--skip-db-update --skip-check-update"
      fi
    fi

    if trivy fs $skip_flags --severity HIGH,CRITICAL --scanners vuln,misconfig,secret --exit-code 1 .; then
      echo "[SUCCESS] Trivy security scan passed."
      # 실제 업데이트를 진행한 경우에만 타임스탬프 최신화
      if [ -z "$skip_flags" ]; then
        echo "$now" > "$timestamp_file" 2>/dev/null
      fi
    else
      return 1
    fi
  elif has_tool trufflehog; then
    echo "Running trufflehog filesystem scan..."
    trufflehog filesystem --no-update --fail .
    echo "[SUCCESS] Trufflehog secret scan passed."
  else
    echo "[WARNING] Neither trivy nor trufflehog is installed. Skipping security scanning."
  fi
}

# 12. FinOps Cost Validation (Infracost)
validate_finops_costs() {
  # 커밋 시점이 아닐 경우 비용 검사 생략 (API 호출 제한 절약)
  if [ "${RUN_COST_CHECK:-false}" != "true" ]; then
    echo "--- Step: FinOps Cost Validation (Infracost) ---"
    echo "[INFO] Not in Git commit stage. Skipping cost validation to save API limits."
    return 0
  fi

  local tf_files=()
  while IFS= read -r -d '' file; do
    tf_files+=("$file")
  done < <(find . -maxdepth 3 -name ".*" -prune -o -name "*.tf" -print0 2>/dev/null)

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
      
      # infracost breakdown을 수행하여 비용 항목 확인
      if infracost breakdown --path . > "$cost_output_tmp" 2>/dev/null; then
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

# -----------------------------------------------------------------------------
# Main Orchestration Flow
# -----------------------------------------------------------------------------
# 전역 캐시 변수 선언 (쉘 연산 호출 중복 제거)
GLOBAL_TF_HASH=""

main() {
  # 스크립트 기동 직후 1회만 해시 연산을 수행하여 전역 변수화
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

  # 검증 성공 시 스테이징 캐시 갱신 (변경 대상이 있을 때만 업데이트)
  if [ "$GLOBAL_TF_HASH" != "empty" ] && [ "$GLOBAL_TF_HASH" != "non-git" ]; then
    echo "$GLOBAL_TF_HASH" > "$CACHE_FILE" 2>/dev/null
  fi

  echo "================================================="
  echo "=== All Pre-Flight Checks Passed Successfully ==="
  echo "================================================="
}

# Run execution
main

