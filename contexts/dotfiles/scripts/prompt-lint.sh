#!/usr/bin/env bash
# prompt-lint.sh - Dotfiles Prompt Corpus Consistency Linter
#
# pre-flight-check.sh/k8s-check.sh 등은 "다운스트림 프로젝트의 인프라 코드"를
# 검증하는 스크립트라 contexts/*/scripts/*-check.sh 자동 위임 대상에 포함된다.
# 이 스크립트는 그 반대로 "dotfiles 저장소 자신의 프롬프트 원본(.md)"이 스스로
# 일관성을 유지하는지 검증하는 것이 목적이라, 일부러 `-check.sh` 네이밍을 쓰지
# 않아 다른 프로젝트에서 실행되는 pre-flight-check.sh의 자동 위임에 걸리지 않는다.
#
# ERROR: 명확한 결함(링크 깨짐, SSOT 목록 불일치, 코드펜스 깨짐) -> 종료 코드 1
# WARNING: 사람/AI의 추가 판단이 필요한 후보(고아 파일, 크로스 스킬 중복 후보,
#          크기 제약 초과) -> 통과는 시키되 눈에 띄게 출력

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT" || {
  echo "[ERROR] 저장소 루트($REPO_ROOT)로 이동할 수 없습니다." >&2
  exit 1
}

CONTEXTS_DIR="$REPO_ROOT/contexts"
EXIT_CODE=0

echo "======================================================"
echo "=== Prompt Corpus Lint Started ==="
echo "======================================================"

# -----------------------------------------------------------------------------
# 1. 자가비판 SSOT 모듈 목록 vs 실제 파일 목록 대조
# -----------------------------------------------------------------------------
check_ssot_module_lists() {
  echo "--- Step: Self-Critique SSOT Module List Consistency ---"
  local core_files
  mapfile -d '' -t core_files < <(grep -lE "공통 자가 비판 절차 \(전 .+ 모듈 SSOT\)" "$CONTEXTS_DIR"/*/references/*.md 2>/dev/null | tr '\n' '\0')

  if [ "${#core_files[@]}" -eq 0 ]; then
    echo "[WARNING] 공통 자가 비판 절차 SSOT 선언 파일을 찾지 못했습니다."
    return
  fi

  local corefile skill_dir declared_line declared actual own_prefix
  for corefile in "${core_files[@]}"; do
    [ -z "$corefile" ] && continue
    skill_dir=$(dirname "$(dirname "$corefile")")
    own_prefix=$(basename "$corefile" | grep -oE '^[0-9]{3}')

    declared_line=$(grep "공통 자가 비판 절차" "$corefile")
    declared=$(echo "$declared_line" | grep -oE '\([0-9]{3}(, [0-9]{3})*\)' | tr -d '()' | tr -d ' ' | tr ',' '\n' | sort -u)

    actual=$(find "$skill_dir/references" -maxdepth 1 -name "*.md" -printf '%f\n' 2>/dev/null |
      grep -oE '^[0-9]{3}' | grep -v "^${own_prefix}$" | sort -u)

    if [ "$declared" != "$actual" ]; then
      echo "❌ [ERROR] SSOT 모듈 목록 불일치: $corefile" >&2
      echo "    선언된 목록: $(echo "$declared" | tr '\n' ' ')" >&2
      echo "    실제 파일  : $(echo "$actual" | tr '\n' ' ')" >&2
      EXIT_CODE=1
    fi
  done
  echo "[INFO] SSOT 모듈 목록 대조 완료."
}

# -----------------------------------------------------------------------------
# 2. 참조 링크(references: frontmatter, 본문 내 경로) 무결성
# -----------------------------------------------------------------------------
check_reference_links() {
  echo "--- Step: Reference Link Integrity ---"
  local f ref
  while IFS= read -r -d '' f; do
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      [ -f "$REPO_ROOT/$ref" ] || {
        echo "❌ [ERROR] 깨진 참조 링크: $f -> $ref" >&2
        EXIT_CODE=1
      }
    done < <(grep -ohE 'contexts/[a-z-]+/(references/[0-9]{3}-[a-z0-9-]+\.md|SKILL\.md|scripts/[a-z0-9-]+\.sh)' "$f" 2>/dev/null | sort -u)
  done < <(find "$CONTEXTS_DIR" -name "*.md" -print0)
  echo "[INFO] 참조 링크 검사 완료."
}

# -----------------------------------------------------------------------------
# 3. 라우팅 테이블 고아 파일 탐지 (SKILL.md에 언급되지 않은 reference 파일)
# -----------------------------------------------------------------------------
check_orphaned_files() {
  echo "--- Step: Orphaned Reference File Detection ---"
  local skill_dir skill_md fname
  for skill_dir in "$CONTEXTS_DIR"/*/; do
    skill_md="${skill_dir}SKILL.md"
    [ -f "$skill_md" ] || continue
    [ -d "${skill_dir}references" ] || continue
    for f in "${skill_dir}references"/*.md; do
      [ -f "$f" ] || continue
      fname=$(basename "$f")
      grep -q "$fname" "$skill_md" || echo "[WARNING] 고아 후보(라우팅 테이블에 없음): $f"
    done
  done
  echo "[INFO] 고아 파일 검사 완료."
}

# -----------------------------------------------------------------------------
# 4. 파일 크기 제약 (150줄) 검사
# -----------------------------------------------------------------------------
check_file_size() {
  echo "--- Step: File Size Constraint (<=150 lines) ---"
  local f lines
  while IFS= read -r -d '' f; do
    lines=$(wc -l <"$f")
    [ "$lines" -gt 150 ] && echo "[WARNING] 150줄 제약 초과: $f (${lines}줄)"
  done < <(find "$CONTEXTS_DIR" -path "*/references/*.md" -print0)
  echo "[INFO] 파일 크기 검사 완료."
}

# -----------------------------------------------------------------------------
# 5. 최종 검토일(reviewed) 신선도 검사 (기본 90일)
# -----------------------------------------------------------------------------
check_staleness() {
  echo "--- Step: Reviewed-Date Staleness (>90 days) ---"
  local staleness_days=90
  local today_epoch reviewed reviewed_epoch age_days f
  today_epoch=$(date +%s)

  while IFS= read -r -d '' f; do
    reviewed=$(grep -m1 "^reviewed:" "$f" 2>/dev/null | awk '{print $2}' || true)
    if [ -z "$reviewed" ]; then
      echo "[WARNING] reviewed 필드 없음: $f"
      continue
    fi
    reviewed_epoch=$(date -d "$reviewed" +%s 2>/dev/null || echo "")
    if [ -z "$reviewed_epoch" ]; then
      echo "[WARNING] reviewed 날짜 형식 파싱 실패: $f ($reviewed)"
      continue
    fi
    age_days=$(((today_epoch - reviewed_epoch) / 86400))
    [ "$age_days" -gt "$staleness_days" ] && echo "[WARNING] ${age_days}일간 미검토(기준 ${staleness_days}일): $f"
  done < <(find "$CONTEXTS_DIR" \( -name "SKILL.md" -o -path "*/references/*.md" \) -print0)
  echo "[INFO] 신선도 검사 완료."
}

# -----------------------------------------------------------------------------
# 5. 크로스 클라우드/스킬 벤더 용어 오염 검사 (고정밀 패턴만)
# -----------------------------------------------------------------------------
check_vendor_leakage() {
  echo "--- Step: Cross-Vendor Terminology Leakage ---"
  local hit

  # azurecr.io는 azure/ 폴더 밖에서 등장하면 안 됨 (예시 코드에 벤더 종속 레지스트리 하드코딩)
  hit=$(grep -rl "azurecr\.io" "$CONTEXTS_DIR" --include="*.md" 2>/dev/null | grep -v "^$CONTEXTS_DIR/azure/" || true)
  [ -n "$hit" ] && {
    echo "❌ [ERROR] azure 폴더 밖에서 azurecr.io 발견:" >&2
    echo "    ${hit//$'\n'/$'\n    '}" >&2
    EXIT_CODE=1
  }

  # "IAM/RBAC" 병기는 aws 폴더에서는 부정확한 표현 (AWS는 IAM/RBAC를 공식 병기하지 않음)
  hit=$(grep -rl "IAM/RBAC" "$CONTEXTS_DIR/aws" --include="*.md" 2>/dev/null || true)
  [ -n "$hit" ] && {
    echo "❌ [ERROR] aws 폴더에서 'IAM/RBAC' 병기 발견 (Azure 전용 표현):" >&2
    echo "    ${hit//$'\n'/$'\n    '}" >&2
    EXIT_CODE=1
  }

  echo "[INFO] 벤더 용어 오염 검사 완료."
}

# -----------------------------------------------------------------------------
# 6. 코드펜스 짝 검사
# -----------------------------------------------------------------------------
check_code_fences() {
  echo "--- Step: Code Fence Balance ---"
  local f n
  while IFS= read -r -d '' f; do
    n=$(grep -c '^```' "$f" 2>/dev/null || true)
    if [ $((n % 2)) -ne 0 ]; then
      echo "❌ [ERROR] 코드펜스 짝이 맞지 않음: $f" >&2
      EXIT_CODE=1
    fi
  done < <(find "$CONTEXTS_DIR" -name "*.md" -print0)
  echo "[INFO] 코드펜스 검사 완료."
}

# -----------------------------------------------------------------------------
# 7. Halt & Clarify / Hard Block 등급 휴리스틱 (경고 전용)
# -----------------------------------------------------------------------------
check_severity_tag_heuristic() {
  echo "--- Step: Halt & Clarify vs Hard Block Severity Heuristic (Warning Only) ---"
  # base.AGENTS.md 정의상 "보안 취약점 발견"은 Hard Block이 맞다. 아래 고위험
  # 키워드가 포함된 중단 조건 줄인데 Halt & Clarify로 태깅되어 있으면, 실제로는
  # Hard Block이어야 할 후보일 확률이 높으므로 사람/AI의 재검토를 요청한다.
  local risk_keywords='privileged|hostNetwork|평문|자격 증명|시크릿.*유출|credential|secret.*leak|0\.0\.0\.0/0|CVE|readOnlyRootFilesystem'
  local f hits
  while IFS= read -r -d '' f; do
    hits=$(grep -E "$risk_keywords" "$f" 2>/dev/null | grep "Halt & Clarify" || true)
    [ -n "$hits" ] && {
      echo "[WARNING] 고위험 키워드가 있는데 Halt & Clarify로 태깅됨 (Hard Block 검토 필요): $f"
      echo "    ${hits//$'\n'/$'\n    '}"
    }
  done < <(find "$CONTEXTS_DIR" -name "*.md" -print0)
  echo "[INFO] 등급 휴리스틱 검사 완료."
}

# -----------------------------------------------------------------------------
# 8. 크로스 스킬 개념 중복 후보 탐지 (경고 전용, 자동 수정 없음)
# -----------------------------------------------------------------------------
check_cross_skill_duplication() {
  echo "--- Step: Cross-Skill Concept Duplication Candidates (Warning Only) ---"
  # aws/azure 미러링(같은 개념이 두 클라우드 스킬에 각각 존재)은 의도된 구조이므로
  # 그 둘만 겹치는 경우는 제외하고, 그 외 스킬(k8s/aiops/containers/observability/
  # multi-cloud)까지 걸치면 실수일 확률이 높아 경고한다.
  # 다른 스킬로 위임하는 문장("위임"/"참조하십시오")에서 개념 이름만 언급하는 것은
  # 실제 내용 중복이 아니므로, 그런 위임 라인은 제외하고 "실제 내용으로" 등장하는
  # 파일만 집계한다.
  local concepts=("SLI/SLO" "RED (Rate" "Error Budget" "OpenTelemetry" "카디널리티")
  local concept files skill_count
  for concept in "${concepts[@]}"; do
    files=$(grep -E "$concept" "$CONTEXTS_DIR"/*/references/*.md 2>/dev/null |
      grep -v "위임\|참조하십시오\|참조하고" |
      cut -d: -f1 | sort -u || true)
    [ -z "$files" ] && continue
    skill_count=$(echo "$files" | sed -E "s#$CONTEXTS_DIR/([a-z-]+)/.*#\1#" | sort -u | grep -vcE "^(aws|azure)$")
    if [ "$skill_count" -ge 2 ] || { [ "$skill_count" -ge 1 ] && echo "$files" | grep -qE "$CONTEXTS_DIR/(aws|azure)/"; }; then
      echo "[WARNING] '$concept' 개념이 aws/azure 미러링 범위를 넘어 여러 스킬에 실질적으로 등장 (중복 검토 필요):"
      echo "    ${files//$'\n'/$'\n    '}"
    fi
  done
  echo "[INFO] 크로스 스킬 중복 후보 검사 완료."
}

main() {
  check_ssot_module_lists
  check_reference_links
  check_orphaned_files
  check_file_size
  check_staleness
  check_vendor_leakage
  check_code_fences
  check_severity_tag_heuristic
  check_cross_skill_duplication

  echo "======================================================"
  if [ "$EXIT_CODE" -eq 0 ]; then
    echo "=== Prompt Corpus Lint Passed (경고는 위 WARNING 참조) ==="
  else
    echo "=== Prompt Corpus Lint Failed — ERROR 항목을 수정하십시오 ==="
  fi
  echo "======================================================"

  exit "$EXIT_CODE"
}

main
