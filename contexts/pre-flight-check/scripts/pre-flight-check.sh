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
  command -v "$1" &>/dev/null || return 1
  # mise shim 파일은 command -v로 항상 발견되지만, 해당 도구의 버전이 현재 디렉토리에서
  # 해석되지 않으면(예: mise 설정이 미치지 못하는 위치) 실제 호출 시점에 실패한다.
  # 각 도구마다 다른 --version 플래그를 흉내내는 대신, mise 자체에 해석 가능 여부를 물어본다.
  if command -v mise &>/dev/null; then
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
    shfmt -d -i 2 "${shell_files[@]}"
  fi

  # zsh 방언은 정적 분석 도구가 지원하지 않으므로 .zsh를 제외한 나머지(.sh, 확장자 없는 훅 파일 등)만 대상으로 삼음
  if [ "$has_shellcheck" -eq 1 ]; then
    local sh_only_files=()
    for f in "${shell_files[@]}"; do
      [[ "$f" != *.zsh ]] && sh_only_files+=("$f")
    done
    if [ "${#sh_only_files[@]}" -gt 0 ]; then
      echo "Running shellcheck..."
      shellcheck "${sh_only_files[@]}"
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
        zsh -n "$f"
      else
        echo "[WARNING] zsh not found, skipping syntax check for: $f"
      fi
    else
      bash -n "$f"
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
    terraform fmt -check -recursive

    echo "Running terraform validate (offline initialization)..."
    if [ ! -d ".terraform" ]; then
      terraform init -backend=false -input=false >/dev/null
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
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t bicep_files < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.bicep' 2>/dev/null)
  fi

  if [ "${#bicep_files[@]}" -gt 0 ] && [ -n "${bicep_files[0]}" ]; then
    if has_tool az && az bicep version &>/dev/null; then
      echo "--- Step: Azure Bicep Validation ---"
      for bf in "${bicep_files[@]}"; do
        [ -z "$bf" ] && continue
        echo "Validating bicep file: $bf"
        # --stdout으로 나오는 컴파일된 ARM JSON만 버리고, 실패 시 원인 진단을 위해 stderr는 그대로 노출한다.
        az bicep build --file "$bf" --stdout >/dev/null
      done
      echo "[SUCCESS] Bicep validation passed."
    else
      echo "[WARNING] Bicep files found but az CLI with bicep extension is not installed."
    fi
  fi
}

# 5. Ansible Validation
validate_ansible() {
  local ansible_files=() staged_roles=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t ansible_files < <(git diff --cached --name-only -z --diff-filter=ACM -- '*playbook*.yml' '*playbook*.yaml' 'site.yml' 'site.yaml' 2>/dev/null)
    mapfile -d '' -t staged_roles < <(git diff --cached --name-only -z --diff-filter=ACM -- 'roles' 2>/dev/null)
  fi

  if { [ "${#ansible_files[@]}" -gt 0 ] && [ -n "${ansible_files[0]}" ]; } || { [ "${#staged_roles[@]}" -gt 0 ] && [ -n "${staged_roles[0]}" ]; }; then
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
      echo "[SUCCESS] Ansible validation passed."
    else
      echo "[WARNING] ansible-lint is not installed. Skipping lint validation."
    fi
  fi
}

# 6. K8s Helm Validation
validate_helm() {
  if [ -f "Chart.yaml" ]; then
    local helm_changed=()
    if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
      mapfile -d '' -t helm_changed < <(git diff --cached --name-only -z --diff-filter=ACM -- 'Chart.yaml' 'values.yaml' 'templates' 2>/dev/null)
    fi
    if [ "${#helm_changed[@]}" -eq 0 ] || [ -z "${helm_changed[0]}" ]; then
      return 0
    fi

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
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t dockerfiles < <(git diff --cached --name-only -z --diff-filter=ACM -- '*Dockerfile*' 2>/dev/null)
  fi

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
      yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${yaml_files[@]}"
      echo "[SUCCESS] YAML format validation passed."
    else
      echo "[WARNING] YAML files found but yamllint is not installed."
    fi
  fi
}

# 10. OPA/Conftest Policy Validation
validate_conftest() {
  local staged_rego=() staged_config=()
  if [ "$GLOBAL_IS_GIT_REPO" -eq 1 ]; then
    mapfile -d '' -t staged_rego < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.rego' 2>/dev/null)
    mapfile -d '' -t staged_config < <(git diff --cached --name-only -z --diff-filter=ACM -- '*.yaml' '*.yml' '*.json' 2>/dev/null)
  fi

  local has_staged_rego=0 has_staged_config=0
  { [ "${#staged_rego[@]}" -gt 0 ] && [ -n "${staged_rego[0]}" ]; } && has_staged_rego=1
  { [ "${#staged_config[@]}" -gt 0 ] && [ -n "${staged_config[0]}" ]; } && has_staged_config=1

  if [ "$has_staged_rego" -eq 1 ] || { [ -d "policy" ] && [ "$has_staged_config" -eq 1 ]; }; then
    if has_tool conftest; then
      echo "--- Step: Conftest Policy Validation ---"
      if [ "$has_staged_rego" -eq 1 ]; then
        # 정책(.rego) 자체가 바뀐 경우: 기존에 이미 존재하던 설정 파일들이 새 정책도
        # 여전히 통과하는지 확인해야 하므로 저장소 전체를 대상으로 검사한다.
        echo "[INFO] Rego policy changed. Testing against the entire repository for regressions."
        conftest test .
      else
        # 정책은 그대로이고 설정 파일만 바뀐 경우: 이번에 변경된 파일만 검사해도
        # (다른 설정 파일은 이미 기존 정책을 통과한 상태이므로) 무관한 재검사를 피할 수 있다.
        conftest test "${staged_config[@]}"
      fi
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
    local skip_flags=()

    local now
    now=$(date +%s)

    if [ -f "$timestamp_file" ]; then
      local last_update
      last_update=$(cat "$timestamp_file" 2>/dev/null || echo 0)
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

# -----------------------------------------------------------------------------
# Main Orchestration Flow
# -----------------------------------------------------------------------------
# 전역 캐시 변수 선언 (쉘 연산 호출 중복 제거)
GLOBAL_IS_GIT_REPO=0
GLOBAL_TF_HASH=""
GLOBAL_STAGED_TF_FILES=()
GLOBAL_STAGED_YAML_FILES=()

main() {
  # Git 저장소 여부 및 여러 검증 함수(shell/bicep/ansible/helm/docker/conftest,
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
