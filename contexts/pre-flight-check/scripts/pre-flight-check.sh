#!/usr/bin/env bash
# pre-flight-check.sh - Modular & Fail-safe IaC/Script Validation Pipeline

set -euo pipefail

echo "============================================="
echo "=== Pre-Flight Validation Pipeline Started ==="
echo "============================================="

# -----------------------------------------------------------------------------
# Common Helpers
# -----------------------------------------------------------------------------
has_tool() {
  command -v "$1" &> /dev/null || return 1
}

# -----------------------------------------------------------------------------
# Validation Sub-modules (Isolated Functions)
# -----------------------------------------------------------------------------

# 1. Shell Script Validation
validate_shell() {
  local shell_files=()
  mapfile -t shell_files < <(find . -maxdepth 3 -not -path '*/.*' -not -path './contexts/*' \( -name "*.sh" -o -name "*.zsh" \) 2>/dev/null)

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
  mapfile -t tf_files < <(find . -maxdepth 3 -not -path '*/.*' -name "*.tf" 2>/dev/null)

  if [ "${#tf_files[@]}" -gt 0 ] && [ -n "${tf_files[0]}" ]; then
    echo "--- Step: Terraform Validation ---"
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
  mapfile -t bicep_files < <(find . -maxdepth 3 -not -path '*/.*' -name "*.bicep" 2>/dev/null)

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
  mapfile -t ansible_files < <(find . -maxdepth 2 -not -path '*/.*' \( -name "*playbook*.yml" -o -name "*playbook*.yaml" -o -name "site.yml" -o -name "site.yaml" \) 2>/dev/null)

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
  mapfile -t k8s_manifests < <(find . -maxdepth 4 -not -path '*/.*' -not -path './contexts/*' -not -path '*/templates/*' \( -name "*.yaml" -o -name "*.yml" \) -exec grep -lE "^kind:" {} + 2>/dev/null)

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
  mapfile -t dockerfiles < <(find . -maxdepth 3 -not -path '*/.*' \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "Dockerfile-*" \) 2>/dev/null)

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
  mapfile -t yaml_files < <(find . -maxdepth 4 -not -path '*/.*' -not -path './contexts/*' -not -path '*/templates/*' \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)

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
  mapfile -t rego_files < <(find . -maxdepth 3 -not -path '*/.*' -name "*.rego" 2>/dev/null)

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
    trivy fs --severity HIGH,CRITICAL --scanners vuln,misconfig,secret --exit-code 1 .
    echo "[SUCCESS] Trivy security scan passed."
  elif has_tool trufflehog; then
    echo "Running trufflehog filesystem scan..."
    trufflehog filesystem --no-update --fail .
    echo "[SUCCESS] Trufflehog secret scan passed."
  else
    echo "[WARNING] Neither trivy nor trufflehog is installed. Skipping security scanning."
  fi
}

# -----------------------------------------------------------------------------
# Main Orchestration Flow
# -----------------------------------------------------------------------------
main() {
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

  echo "================================================="
  echo "=== All Pre-Flight Checks Passed Successfully ==="
  echo "================================================="
}

# Run execution
main

