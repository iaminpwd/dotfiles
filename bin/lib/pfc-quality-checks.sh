#!/usr/bin/env bash
# pfc-quality-checks.sh - pre-flight-check.sh 의 코드 품질/보안 검증 모듈
# (Shell/Docker/YAML/Conftest/Security/FinOps). pfc-iac-checks.sh 와 분리 원칙이 동일하다:
# 오케스트레이션과 GLOBAL_* 전역 상태는 pre-flight-check.sh 에 남고, 이 파일은 source 되어
# 그 전역 상태(PFC_SCRIPT_DIR, GLOBAL_TARGET_TF_FILES, tf_cache_status 등)를 그대로 공유한다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.

# 연장 지원(Extended Support/LTS) 유료화 항목 감지 패턴. validate_finops_costs 가 쓰고,
# test-finops.sh 가 이 파일을 source 해 같은 값을 검증한다(패턴을 테스트에 복제하면 본체만
# 고쳤을 때 테스트가 통과해 버려 회귀를 못 잡는다 — 실제로 그 상태였다).
#
# LTS 는 반드시 단어 경계를 함께 봐야 한다. 예전엔 `LTS` 를 -i 로 그냥 찾아서, 부분 문자열로
# "lts" 를 품는 흔한 단어가 전부 걸렸다 — defaults / results / faults / vaults / halts.
# 실측 재현: `resource "aws_s3_bucket" "results"` 하나만 있어도 infracost 출력의
# `aws_s3_bucket.results` 줄이 매치되어 "Extended Support 추가 요금 감지"로 커밋이 막혔다.
# 이 검증기는 전역 core.hooksPath 훅이라 임의 저장소가 그 오탐을 그대로 맞는다.
#
# \b 대신 문자 클래스를 쓰는 이유는 이식성이다. 이 훅은 macOS 에서도 도는데 BSD grep 은
# \b 를 GNU 와 같게 해석한다는 보장이 없다(같은 사유로 아래 trivy 출력 정리도 sed -E 를 쓴다).
PFC_EXTENDED_SUPPORT_PATTERN='Extended Support|Long Term Support|(^|[^A-Za-z])LTS([^A-Za-z]|$)'

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
      # 하나라도 있으면 exit 1 이므로 정상 코드가 커밋 중단으로 이어진다.
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

    # DS-0002(컨테이너가 root로 실행됨) 하드 블록. hadolint에는 이 룰이 없다.
    # validate_security()의 trivy misconfig 스캔이 같은 DS-0002를 이미 경고로는 잡고
    # 있었지만, db-sg-checker.sh 급의 오탐 거의 없는 기초 항목이라 다른 하드 게이트들과
    # 같은 강제력으로 맞춘다. container-hardening-gate.sh는 파일 경로를 받으면 trivy
    # conf로 그 경로만 검사하고 이미지 스캔 분기(릴리즈 단계 책임)는 타지 않는다.
    # -x 가 아니라 -f 로 본다. 아래에서 `bash <경로>` 로 부르므로 실행 비트는 필요 없는데,
    # -x 로 판정하면 비트가 없는 순간 이 하드 게이트가 아무 메시지 없이 사라진다(실측:
    # chmod -x 후 root 유저 Dockerfile 이 exit 0 으로 통과했다). git 이 100755 를 추적하니
    # 정상 클론에서는 드러나지 않지만, core.fileMode=false 환경이나 권한을 보존하지 않는
    # 복사 경로에서 조용히 무력화된다. 바로 위 validate_shell 의 idempotency 호출이 같은
    # 이유로 이미 -f 를 쓴다.
    local HARDENING_SCRIPT="$PFC_SCRIPT_DIR/../linters/container-hardening-gate.sh"
    if [ -f "$HARDENING_SCRIPT" ]; then
      local dockerfile
      for dockerfile in "${dockerfiles[@]}"; do
        if ! bash "$HARDENING_SCRIPT" "$dockerfile"; then
          echo "❌ [ERROR] $dockerfile 컨테이너 하드닝 검사(DS-0002)에 실패하여 커밋이 중단되었습니다." >&2
          return 1
        fi
      done
    fi

    # syft(SBOM)/grype(CVE)의 소스 스캔은 여기 없다: 대상 매니페스트는 validate_security의
    # `trivy fs --scanners vuln`이 이미 같은 저장소를 훑고, syft는 게이트도 아니라 SBOM
    # 테이블을 stdout에 통째로 출력해 순수 노이즈만 남긴다. 이미지 레이어 취약점(vuln/
    # SBOM/서명) 검사는 릴리즈 단계 책임이므로 제외.
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
    # --skip-dirs: 의도적 위반을 담은 회귀 테스트 픽스처를 제외하여 노이즈 방지.
    # 끝의 * 필수 — 실제 픽스처 디렉토리 21개 중 12개가 fixtures-sam / fixtures-shell /
    # fixtures-conftest 처럼 접미사형이라, 예전 패턴('**/tests/fixtures')은 정확히
    # 'fixtures' 인 9개만 걸러내고 나머지는 그대로 스캔해 노이즈를 냈다.
    #
    # 위 1번 시크릿 스캔에는 의도적으로 --skip-dirs를 걸지 않는다. 그쪽은 하드 블록이라
    # 제외 범위를 넓히면 픽스처 디렉토리에 실수로 들어간 진짜 자격 증명을 놓치게 된다
    # (노이즈 감소보다 유출 차단이 우선).
    #
    # 이 스캔은 커밋을 막지 않는 "경고 전용"인데 비용은 위 시크릿 스캔의 3배 이상이고
    # (실측: 0.2s 대 0.7s, 저장소가 클수록 격차가 벌어진다), 대상 필터를 타지 않아
    # README 한 줄만 스테이징해도 저장소 전체를 훑는다. 이 검증기는 전역 core.hooksPath
    # 훅이라 임의 저장소의 매 커밋이 그 비용을 그대로 낸다.
    # 그래서 커밋 경로(staged)와 AI 편집 훅 경로(explicit)에서는 생략하고, 회귀 검증
    # 모드(--all/--changed → just verify, CI, pre-push)에서만 돌린다. 차단력은 그대로다:
    # 하드 블록인 위 시크릿 스캔은 모드와 무관하게 항상, 저장소 전체를, --skip-dirs 없이
    # 검사한다. 여기서 줄어드는 것은 "경고를 언제 보여줄 것인가"뿐이다.
    if [ "$GLOBAL_TARGET_MODE" = "all" ] || [ "$GLOBAL_TARGET_MODE" = "changed" ]; then
      log_info "[INFO] Running trivy vulnerability & misconfig scan (Warnings only)..."
      local tmp_vuln
      tmp_vuln=$(mktemp)
      # Trivy --exit-code 0 시 출력 파싱으로 취약점 존재 여부 및 실행 실패 판별
      if trivy fs -q "${skip_flags[@]}" --severity HIGH,CRITICAL --scanners vuln,misconfig --exit-code 0 \
        --skip-dirs '**/tests/fixtures*' . >"$tmp_vuln" 2>&1; then
        # 결과 테이블에 취약점이 있는지 확인 (Total: 0 이 아닌 경우)
        # Trivy 출력에 ANSI 색상 코드가 포함되어 있을 수 있으므로 제거 후 검사
        #
        # `sed -r` 과 `\x1B` 는 둘 다 GNU sed 전용이다. 이 검증기는 전역 core.hooksPath
        # 훅으로 macOS 에서도 도는데, BSD sed 는 -r 을 모르는 옵션으로 거절하고 \x 이스케이프도
        # 해석하지 않는다. 그러면 이 대입이 실패하고 set -e 가 pre-flight-check 전체를
        # 죽인다. POSIX 호환인 -E 와, ESC 문자를 printf 로 만들어 넘기는 방식으로 바꾼다.
        local clean_out esc
        esc=$(printf '\033')
        clean_out=$(sed -E "s/${esc}\[[0-9;]*[mK]//g" "$tmp_vuln")
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
    else
      log_info "[INFO] '$GLOBAL_TARGET_MODE' 모드 — 경고 전용 vuln/misconfig 스캔은 --all/--changed 에서만 수행합니다."
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
      # trap ... RETURN 을 쓰지 않는다: bash에서 함수 스코프가 아니라 프로세스 전역이라
      # 이 함수가 끝난 뒤에도 남아 있다가 이후 리턴되는 다른 함수에서 발동해 이미 스코프를
      # 벗어난 $cost_output_tmp 를 참조하며 죽을 수 있다. 이 함수 내부의 모든 종료 경로가
      # 이미 rm -f 로 수동 정리하므로 트랩 없이도 누수가 없다.

      # infracost breakdown을 수행하여 비용 항목 확인
      if infracost breakdown --path . >"$cost_output_tmp" 2>/dev/null; then
        if grep -E -qi "$PFC_EXTENDED_SUPPORT_PATTERN" "$cost_output_tmp"; then
          echo "[ERROR] Extended Support 또는 LTS (연장 지원) 추가 요금이 발생하는 리소스가 감지되었습니다." >&2
          echo "검출된 유효 비용 항목:" >&2
          grep -E -i "$PFC_EXTENDED_SUPPORT_PATTERN" "$cost_output_tmp" >&2
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
