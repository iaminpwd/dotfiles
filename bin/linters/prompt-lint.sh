#!/usr/bin/env bash
# prompt-lint.sh - Dotfiles Prompt Corpus Consistency Linter
#
# 프롬프트 원본(.md) 자가 검증용 스크립트
# (타 프로젝트 인프라 검증용이 아니므로 preflight/ 위임 경로 밖에 배치)
#
# ERROR: 명확한 결함(링크 깨짐, SSOT 목록 불일치, 코드펜스 깨짐) -> 종료 코드 1
# WARNING: 사람/AI의 추가 판단이 필요한 후보(고아 파일, 크로스 스킬 중복 후보,
#          크기 제약 초과) -> 통과는 시키되 눈에 띄게 출력

set -euo pipefail

# Setup Quiet Mode Logging
log_info() {
  # Default to QUIET=1 for AI token savings, unless explicitly set to 0
  if [ "${QUIET:-1}" != "1" ]; then
    echo "$@"
  fi
}

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT" || {
  echo "[ERROR] 저장소 루트($REPO_ROOT)로 이동할 수 없습니다." >&2
  exit 1
}

CONTEXTS_DIR="$REPO_ROOT/contexts"
EXIT_CODE=0

log_info "======================================================"
log_info "=== Prompt Corpus Lint Started ==="
log_info "======================================================"

# -----------------------------------------------------------------------------
# 1. 자가비판 SSOT 모듈 목록 vs 실제 파일 목록 대조
# -----------------------------------------------------------------------------
check_ssot_module_lists() {
  log_info "--- Step: Self-Critique SSOT Module List Consistency ---"
  local core_files
  mapfile -d '' -t core_files < <(grep -lZE "공통 자가 비판 절차 \(전 .+ 모듈 SSOT\)" "$CONTEXTS_DIR"/*/references/*.md 2>/dev/null || true)

  if [ "${#core_files[@]}" -eq 0 ]; then
    log_info "[WARNING] 공통 자가 비판 절차 SSOT 선언 파일을 찾지 못했습니다."
    return
  fi

  local corefile skill_dir declared_line declared actual own_prefix
  for corefile in "${core_files[@]}"; do
    [ -z "$corefile" ] && continue
    skill_dir=$(dirname "$(dirname "$corefile")")
    # grep 무매치(exit 1) 시 pipefail에 의한 스크립트 중단 방지를 위해 빈 문자열로 흡수
    own_prefix=$(basename "$corefile" | grep -oE '^[0-9]{3}' || true)

    declared_line=$(grep "공통 자가 비판 절차" "$corefile" || true)
    declared=$(grep -oE '\([0-9]{3}(, [0-9]{3})*\)' <<<"$declared_line" | tr -d '()' | tr -d ' ' | tr ',' '\n' | sort -u || true)

    actual=$(find "$skill_dir/references" -path "*/.archive/*" -prune -o -maxdepth 1 -name "*.md" -printf '%f\n' 2>/dev/null |
      grep -oE '^[0-9]{3}' | grep -v "^${own_prefix}$" | sort -u || true)

    if [ "$declared" != "$actual" ]; then
      echo "❌ [ERROR] SSOT 모듈 목록 불일치: $corefile" >&2
      echo "    선언된 목록: $(echo "$declared" | tr '\n' ' ')" >&2
      echo "    실제 파일  : $(echo "$actual" | tr '\n' ' ')" >&2
      EXIT_CODE=1
    fi
  done
  log_info "[INFO] SSOT 모듈 목록 대조 완료."
}

# -----------------------------------------------------------------------------
# 2. 참조 링크(references: frontmatter, 본문 내 경로) 무결성
# -----------------------------------------------------------------------------
check_reference_links() {
  log_info "--- Step: Reference Link Integrity ---"
  local match f ref
  # 하위 디렉토리(preflight, tests/lib 등) 패턴 누락으로 인한 사각지대 제거
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    f="${match%%:*}"
    ref="${match#*:}"
    [ -f "$REPO_ROOT/$ref" ] || {
      echo "❌ [ERROR] 깨진 참조 링크: $f -> $ref" >&2
      EXIT_CODE=1
    }
  done < <(grep -rHoE 'contexts/[a-z-]+/(references/[0-9]{3}-[a-z0-9_-]+\.md|SKILL\.md|role\.[a-z0-9_-]+\.md|(scripts|tests)/([a-z0-9_-]+/)?[a-z0-9_-]+\.(sh|py)|evals/[a-z0-9_-]+/[a-z0-9_-]+\.(sh|tsv))' "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".archive" 2>/dev/null | sort -u || true)
  log_info "[INFO] 참조 링크 검사 완료."
}

# -----------------------------------------------------------------------------
# 3. 라우팅 테이블 고아 파일 탐지 (SKILL.md에 언급되지 않은 reference 파일)
# -----------------------------------------------------------------------------
check_orphaned_files() {
  log_info "--- Step: Orphaned Reference File Detection ---"
  local skill_dir skill_md fname
  for skill_dir in "$CONTEXTS_DIR"/*/; do
    [ "$(basename "$skill_dir")" = ".archive" ] && continue
    skill_md="${skill_dir}SKILL.md"
    [ -f "$skill_md" ] || continue
    [ -d "${skill_dir}references" ] || continue
    for f in "${skill_dir}references"/*.md; do
      [ -f "$f" ] || continue
      fname=$(basename "$f")
      grep -Fq "$fname" "$skill_md" || log_info "[WARNING] 고아 후보(라우팅 테이블에 없음): $f"
    done
  done
  log_info "[INFO] 고아 파일 검사 완료."
}

# -----------------------------------------------------------------------------
# 3b. 문서가 "살아 있는 조항"으로 인용한 조항이 실제 룰북에 존재하는지 검사
# -----------------------------------------------------------------------------
check_documented_clause_existence() {
  log_info "--- Step: Documented Clause Existence ---"
  # 조항 단위 드리프트 탐지: 삭제/변경된 조항이 문서(README 등)에 인용 방치되는 현상 방지
  local readme="$CONTEXTS_DIR/README.md"
  [ -f "$readme" ] || {
    log_info "[INFO] 조항 실재성 검사 건너뜀 (contexts/README.md 없음)."
    return
  }

  # 조항명 추출: -E 정규식 사용 (macOS 이식성). 괄호 주석 공백 처리 주의.
  local names_file found_file
  names_file=$(mktemp)
  found_file=$(mktemp)
  sed -nE 's/^[[:space:]]*[-*][[:space:]]+\*\*(\[[^]]+\][[:space:]]*)?([A-Za-z][A-Za-z0-9 &'"'"'\/-]*[A-Za-z0-9])[[:space:]]*(\([^)]*\))?[[:space:]]*:\*\*.*/\2/p' \
    "$readme" | sort -u >"$names_file"

  # 성능 최적화: 순회 반복 대신 문서 전체에서 실재 이름 집합을 한 번만 추출하여 대조
  #
  # 전문을 변수에 모아 `printf ... | grep -q` 로 넘기는 방식은 쓰지 않는다. grep 이 첫
  # 매치에서 종료하며 stdin 을 닫고, 그 SIGPIPE 로 printf 가 141 을 반환하는데 set -o
  # pipefail 이 그것을 파이프라인 결과로 채택해 "찾았는데 못 찾음"으로 뒤집힌다
  # (2026-07-28 실측: 실재하는 조항 20건이 전부 오탐).
  if [ -s "$names_file" ]; then
    grep -rhoFf "$names_file" --include="*.md" --exclude-dir=".archive" --exclude="README.md" "$CONTEXTS_DIR" 2>/dev/null |
      sort -u >"$found_file" || true

    local name line_no
    while IFS= read -r name; do
      grep -qxF -- "$name" "$found_file" && continue
      # 행 번호는 실패한 조항에만 되찾는다. 정상 경로에서는 추가 비용이 들지 않는다.
      line_no=$(grep -nF -- "$name" "$readme" | head -1 | cut -d: -f1)
      echo "❌ [ERROR] 룰북에 없는 조항을 문서가 인용: $readme:${line_no:-?} -> '$name'" >&2
      echo "    조항이 삭제·개명되었거나 문서가 낡았습니다. 양쪽을 일치시키십시오." >&2
      EXIT_CODE=1
    done <"$names_file"
  fi
  rm -f "$names_file" "$found_file"
  log_info "[INFO] 조항 실재성 검사 완료."
}

# -----------------------------------------------------------------------------
# 4. 파일 크기 제약 (150줄) 검사
# -----------------------------------------------------------------------------
check_file_size() {
  log_info "--- Step: File Size Constraint (rule=150 / library=250 lines) ---"
  find "$CONTEXTS_DIR" -path "*/.archive/*" -prune -o -path "*/references/*.md" -print0 | xargs -0 wc -l 2>/dev/null | awk '
    $2 != "total" && $2 != "" {
      lines = $1;
      f = $2;
      limit = (f ~ /-library\.md$/) ? 250 : 150;
      if (lines > limit) {
        print "[WARNING] " limit "줄 제약 초과: " f " (" lines "줄)"
      }
    }'
  log_info "[INFO] 파일 크기 검사 완료."
}

# -----------------------------------------------------------------------------
# 5. 크로스 클라우드/스킬 벤더 용어 오염 검사 (고정밀 패턴만)
# -----------------------------------------------------------------------------
check_vendor_leakage() {
  log_info "--- Step: Cross-Vendor Terminology Leakage ---"
  local hit

  # azurecr.io는 azure/ 폴더 안에서만 사용할 것 (예시 코드에 벤더 종속 레지스트리 하드코딩)
  hit=$(grep -rl "azurecr\.io" "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".archive" 2>/dev/null | grep -v "^$CONTEXTS_DIR/azure/" || true)
  [ -n "$hit" ] && {
    echo "❌ [ERROR] azure 폴더 밖에서 azurecr.io 발견:" >&2
    echo "    ${hit//$'\n'/$'\n    '}" >&2
    EXIT_CODE=1
  }

  # "IAM/RBAC" 병기는 aws 폴더에서는 부정확한 표현 (AWS는 IAM/RBAC를 공식 병기하지 않음)
  hit=$(grep -rl "IAM/RBAC" "$CONTEXTS_DIR/aws" --include="*.md" --exclude-dir=".archive" 2>/dev/null || true)
  [ -n "$hit" ] && {
    echo "❌ [ERROR] aws 폴더에서 'IAM/RBAC' 병기 발견 (Azure 전용 표현):" >&2
    echo "    ${hit//$'\n'/$'\n    '}" >&2
    EXIT_CODE=1
  }

  log_info "[INFO] 벤더 용어 오염 검사 완료."
}

# -----------------------------------------------------------------------------
# 6. 코드펜스 짝 검사
# -----------------------------------------------------------------------------
check_code_fences() {
  log_info "--- Step: Code Fence Balance ---"
  local unclosed
  unclosed=$(find "$CONTEXTS_DIR" -path "*/.archive/*" -prune -o -name "*.md" -print0 | xargs -0 awk '
    BEGIN { fail = 0; }
    FNR == 1 {
      if (count % 2 != 0) {
        print current_file
        fail = 1
      }
      current_file = FILENAME
      count = 0
    }
    /^```/ { count++ }
    END {
      if (count % 2 != 0) {
        print current_file
        fail = 1
      }
      if (fail) exit 1;
    }
  ' || true)
  if [ -n "$unclosed" ]; then
    # 공백 포함 경로 오작동 방지를 위해 for 대신 while read 사용
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo "❌ [ERROR] 코드펜스 짝이 맞지 않음: $f" >&2
    done <<<"$unclosed"
    EXIT_CODE=1
  fi
  log_info "[INFO] 코드펜스 검사 완료."
}

# -----------------------------------------------------------------------------
# 7. Halt & Clarify / Hard Block 등급 휴리스틱 (경고 전용)
# -----------------------------------------------------------------------------
check_severity_tag_heuristic() {
  log_info "--- Step: Halt & Clarify vs Hard Block Severity Heuristic (Warning Only) ---"
  # 보안 취약점 등 고위험 키워드가 포함된 경우 Hard Block 등급 상향 필요성 알림
  local risk_keywords='privileged|hostNetwork|평문|자격 증명|시크릿.*유출|credential|secret.*leak|0\.0\.0\.0/0|CVE|readOnlyRootFilesystem'
  local hits
  hits=$(grep -rHE "$risk_keywords" "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".archive" 2>/dev/null | grep "Halt & Clarify" || true)
  if [ -n "$hits" ]; then
    echo "$hits" | awk -F':' '{
      file = $1;
      sub(/[^:]+:/, "", $0);
      if (file != last_file) {
        print "[WARNING] 고위험 키워드가 있는데 Halt & Clarify로 태깅됨 (Hard Block 검토 필요): " file;
        last_file = file;
      }
      print "    " $0;
    }'
  fi
  log_info "[INFO] 등급 휴리스틱 검사 완료."
}

# -----------------------------------------------------------------------------
# 7b. MUST 로 태깅됐지만 본문이 선호를 서술하는 조항 탐지 (경고 전용)
# -----------------------------------------------------------------------------
check_prefer_language_tagged_must() {
  log_info "--- Step: Preference Wording Tagged as MUST (Warning Only) ---"
  # 본문에 선호 표현("가급적", "우선 탐색" 등) 포함 시 MUST 대신 PREFER 사용 안내
  local prefer_words='최우선으로 (제안|탐색|시도|고려)|최우선 (제안|탐색)|가급적|우선 탐색|권장합니다|권장하십시오'
  local hits
  hits=$(grep -rHE '^\s*[-*]\s+\*\*\[MUST\]' "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".archive" 2>/dev/null | grep -E "$prefer_words" || true)
  if [ -n "$hits" ]; then
    echo "$hits" | awk -F':' '{
      file = $1;
      sub(/[^:]+:/, "", $0);
      if (file != last_file) {
        print "[WARNING] MUST 인데 본문이 선호를 서술함 (PREFER 재등급 검토): " file;
        last_file = file;
      }
      print "    " $0;
    }'
  fi
  log_info "[INFO] 선호 표현 등급 검사 완료."
}

# -----------------------------------------------------------------------------
# 8. 크로스 스킬 개념 중복 후보 탐지 (경고 전용, 자동 수정 없음)
# -----------------------------------------------------------------------------
check_cross_skill_duplication() {
  log_info "--- Step: Cross-Skill Concept Duplication Candidates (Warning Only) ---"
  # aws/azure 미러링(같은 개념이 두 클라우드 스킬에 각각 존재)은 의도된 구조이므로
  # 그 둘만 겹치는 경우는 제외하고, 그 외 스킬(k8s/aiops/containers/observability/
  # multi-cloud)까지 걸치면 실수일 확률이 높아 경고한다.
  # 다른 스킬로 위임하는 문장("위임"/"참조하십시오")에서 개념 이름만 언급하는 것은
  # 실제 내용 중복이 아니므로, 그런 위임 라인은 제외하고 "실제 내용으로" 등장하는
  # 파일만 집계한다.
  # 감시 대상은 "개념"이어야 한다. 제품/도구 이름은 그 도구를 쓰는 모든 도메인에서
  # 정당하게 등장하므로 중복 신호가 되지 못한다. OpenTelemetry 를 이 목록에 두었을 때
  # 걸린 6개 파일(aiops FinOps 파이프라인, aws X-Ray 병기, azure App Insights 병기,
  # observability 벤더중립 계측/Collector 게이트웨이)은 전부 서로 다른 도메인 조항이
  # 도구명만 공유한 것이라 실제 중복이 아니었다(2026-07-27 검토). 개념만 남긴다.
  local concepts=("SLI/SLO" "RED (Rate" "Error Budget" "카디널리티")
  local concept files skill_count
  for concept in "${concepts[@]}"; do
    files=$(grep -E "$concept" "$CONTEXTS_DIR"/*/references/*.md 2>/dev/null |
      grep -v "위임\|참조하십시오\|참조하고" |
      cut -d: -f1 | sort -u || true)
    [ -z "$files" ] && continue
    # grep -vc는 카운트가 0일 때(해당 개념이 aws/azure에만 있을 때) 종료 코드 1을 반환하고,
    # set -euo pipefail 하에서 이 대입이 린터 전체를 아무 메시지 없이 exit 1로 중단시킨다
    # (2026-07-27 실측). 카운트 0은 정상 결과이므로 아래 미러링 검사(275행)와 동일하게 흡수한다.
    skill_count=$(echo "$files" | sed -E "s#$CONTEXTS_DIR/([a-z-]+)/.*#\1#" | sort -u | grep -vcE "^(aws|azure)$" || true)
    if [ "$skill_count" -ge 2 ] || { [ "$skill_count" -ge 1 ] && grep -qE "$CONTEXTS_DIR/(aws|azure)/" <<<"$files"; }; then
      log_info "[WARNING] '$concept' 개념이 aws/azure 미러링 범위를 넘어 여러 스킬에 실질적으로 등장 (중복 검토 필요):"
      echo "    ${files//$'\n'/$'\n    '}"
    fi
  done
  log_info "[INFO] 크로스 스킬 중복 후보 검사 완료."
}

# -----------------------------------------------------------------------------
# 10. aws/azure 미러링 대칭성 검사 (Warning Only)
# -----------------------------------------------------------------------------
check_vendor_mirror_symmetry() {
  log_info "--- Step: aws/azure Mirror Symmetry (Warning Only) ---"
  # aws/azure 미러링은 9번 검사 주석대로 의도된 구조다. 다만 한쪽 벤더에만 조항을
  # 추가하면 드리프트가 쌓이므로(2026-07-26 실측: azure 에 Vulnerability & Data
  # Classification / Continuous Right-Sizing / Managed Observability 대응 조항 누락),
  # 동일 번호 모듈의 조항 수를 대조해 경고한다.
  # 조항명은 벤더 용어로 갈리므로(TGW <-> vWAN, IRSA <-> Workload Identity) 이름이
  # 아니라 개수만 비교해야 대응어 28건을 오탐하지 않는다.
  local f prefix azure_file a_count z_count
  for f in "$CONTEXTS_DIR"/aws/references/*.md; do
    [ -f "$f" ] || continue
    # || true 가 없으면 숫자 접두사 없는 .md 하나만 있어도 grep 이 1을 반환해 린터가
    # 메시지 없이 죽고, 바로 아래 작성자 의도의 가드가 영영 도달하지 못한다(2026-07-27 실측).
    prefix=$(basename "$f" | grep -oE '^[0-9]{3}' || true)
    [ -z "$prefix" ] && continue
    azure_file=$(find "$CONTEXTS_DIR/azure/references" -maxdepth 1 -name "${prefix}-*.md" | head -1)
    if [ -z "$azure_file" ]; then
      log_info "[WARNING] aws/azure 미러링 누락: azure 에 ${prefix} 모듈이 없습니다 ($(basename "$f"))"
      continue
    fi
    a_count=$(grep -cE '^- \*\*\[(MUST|NEVER|PREFER|CRITICAL)\]' "$f" || true)
    z_count=$(grep -cE '^- \*\*\[(MUST|NEVER|PREFER|CRITICAL)\]' "$azure_file" || true)
    if [ "$a_count" -ne "$z_count" ]; then
      log_info "[WARNING] aws/azure 조항 수 불일치 (${prefix}): aws ${a_count}건 / azure ${z_count}건 — 한쪽에만 추가된 규칙이 없는지 확인하십시오"
      echo "    $f"
      echo "    $azure_file"
    fi
  done
  log_info "[INFO] aws/azure 미러링 대칭성 검사 완료."
}

main() {
  check_ssot_module_lists
  check_reference_links
  check_orphaned_files
  check_documented_clause_existence
  check_file_size
  check_vendor_leakage
  check_code_fences
  check_severity_tag_heuristic
  check_prefer_language_tagged_must
  check_cross_skill_duplication
  check_vendor_mirror_symmetry

  log_info "======================================================"
  if [ "$EXIT_CODE" -eq 0 ]; then
    log_info "=== Prompt Corpus Lint Passed (경고는 위 WARNING 참조) ==="
  else
    log_info "=== Prompt Corpus Lint Failed — ERROR 항목을 수정하십시오 ==="
  fi
  log_info "======================================================"

  exit "$EXIT_CODE"
}

main
