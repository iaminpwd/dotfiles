#!/usr/bin/env bash
# pfc-iac-checks.sh - pre-flight-check.sh 의 IaC 검증 모듈 (Terraform/SAM/Bicep/Ansible/Helm/K8s Manifest)
# 970줄이던 pre-flight-check.sh 를 도메인별로 분리한 것 중 하나(다른 하나는
# pfc-quality-checks.sh). 오케스트레이션(main, 인자 파싱, 캐싱)과 GLOBAL_* 전역 상태는
# pre-flight-check.sh 에 그대로 남아있고, 이 파일은 source 되어 그 전역 상태
# (PFC_SCRIPT_DIR, GLOBAL_TARGET_TF_FILES, tf_cache_status 등)를 그대로 공유한다.
# bin/linters/*.sh 처럼 별도 프로세스로 분리하지 않은 이유는, 이 함수들이 캐싱/대상
# 목록 같은 pre-flight-check.sh 의 전역 상태를 공유해야 해서 서브프로세스로 떼어내면
# 그 상태를 매 호출마다 env/인자로 재직렬화해야 하기 때문이다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.

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
      # --skip-path: 의도적 위반을 담은 회귀 테스트 픽스처 제외. 예전엔 dotfiles 전용
      # 경로 4개(contexts/<스킬>/tests/fixtures)를 하나씩 나열했는데, 이 검증기는 전역
      # 훅으로 임의 저장소에서 도는 범용 코드라 남의 저장소엔 맞지 않는 데다,
      # fixtures-conftest / fixtures-sam 처럼 접미사가 붙은 실제 픽스처 디렉토리
      # (전체 21개 중 12개)는 어디에도 안 걸려 그대로 스캔되고 있었다. checkov의
      # --skip-path는 부분 일치라 이 한 패턴이 중첩 경로와 접미사형을 모두 덮는다
      # (실측: contexts/aws/tests/fixtures, contexts/k8s/tests/fixtures-conftest 둘 다 제외).
      if ! checkov --directory . --framework terraform --compact --quiet --soft-fail-on LOW,MEDIUM --skip-path 'tests/fixtures'; then
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
      # ansible-lint.yml이 ansible/ 하위(비표준 위치)에 있어 -c 없이 실행하면
      # auto-discovery가 안 돼 exclude_paths/offline 설정이 무시된다 -> -c로 명시 지정.
      # (참고: 과거 .config/ansible-lint.yml 위치는 auto-discovery 대상이라 -c가 불필요했음)
      # ansible-lint는 실행 중 CWD에 .ansible/ 캐시를 만들어 두고 스스로 치우지 않는다.
      # 그렇다고 무조건 rm -rf 하면 안 된다: 이 검증기는 전역 core.hooksPath 훅을 통해
      # ~/workspace 하위의 임의 저장소에서도 도는데, .ansible/ 은 우리 전용 경로가 아니라
      # `ansible-galaxy collection install -p .ansible` 로 프로젝트 로컬 컬렉션을 두는
      # 실제 관례가 있는 경로다. 소유권 검증 없이 지우면 사용자 데이터를 확인 없이
      # 날린다 — prune-orphan-skills.sh(전부 심볼릭 링크일 때만 삭제)와
      # stow-backup.sh(실제 디렉토리는 절대 미접촉)가 방어하는 "공유 경로를 우리 것으로
      # 오판"과 정확히 같은 클래스의 버그다. 실행 전부터 있었다면 우리가 만든 게 아니므로
      # 그대로 보존하고, 우리가 만들었을 때만 치운다.
      local ansible_cache_owned=0
      [ -e ".ansible" ] || ansible_cache_owned=1

      local lint_cmd=(ansible-lint -c ansible/ansible-lint.yml)
      local lint_rc=0
      "${lint_cmd[@]}" || lint_rc=$?

      if [ "$ansible_cache_owned" -eq 1 ]; then
        rm -rf .ansible
      fi

      if [ "$lint_rc" -ne 0 ]; then
        echo "❌ [ERROR] ansible-lint 지적 사항이 발견되어 커밋이 중단되었습니다." >&2
        return 1
      fi
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
