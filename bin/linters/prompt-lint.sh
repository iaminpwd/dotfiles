#!/usr/bin/env bash
# prompt-lint.sh - Dotfiles Prompt Corpus Consistency Linter
#
# 프롬프트 원본(.md) 자가 검증용 스크립트
# (타 프로젝트 인프라 검증용이 아니므로 preflight/ 위임 경로 밖에 배치)
#
# ERROR: 명확한 결함(링크 깨짐, SSOT 목록 불일치, 코드펜스 깨짐) -> 종료 코드 1
# WARNING: 사람/AI의 추가 판단이 필요한 후보(고아 파일, 크로스 스킬 중복 후보,
#          크기 제약 초과) -> 통과는 시키되 눈에 띄게 출력
#
# [출력 규약] 경고는 log_info 가 아니라 echo 로, 그리고 이어지는 맥락 줄까지 매 줄을
# "[WARNING]" 으로 시작해서 내보낸다. 두 가지 이유가 겹쳐 있다:
#   1. log_info 는 QUIET=1(기본값)에서 억제된다. 훅·run-suite·CI 가 전부 기본값으로
#      돌기 때문에, 경고를 log_info 로 내면 위 "눈에 띄게 출력" 약속이 실제로는
#      어디에서도 지켜지지 않는다.
#   2. run-suite.sh 는 통과한 스크립트의 출력에서 "[WARNING]"/"⚠" 로 시작하는 줄만
#      남기고 나머지를 버린다. 접두사 없는 맥락 줄(파일 경로 등)만 남기면 그 줄들은
#      run-suite 경로에서 버려지고, 직접 실행 시에는 반대로 설명 없는 경로 목록만
#      덩그러니 출력된다(실측된 증상).
# 같은 이유로 bin/lib/tool-probe.sh 의 print_unavailable_tools 도 매 줄에 접두사를
# 붙인다. 새 경고를 추가할 때 이 규약을 따를 것.

set -euo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
PROMPT_LINT_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$PROMPT_LINT_SCRIPT_DIR/../lib/script-init.sh"
# [Good] Dockerfile 예제 검사가 hadolint 가용성을 판정하는 데 쓴다. mise shim 환경에서
# command -v 가 조용히 실패하는 케이스를 tool-probe.sh SSOT 가 해결한다
# (container-hardening-gate.sh 와 동일한 이유·동일한 패턴).
# shellcheck source-path=SCRIPTDIR
source "$PROMPT_LINT_SCRIPT_DIR/../lib/tool-probe.sh"

# 이 스크립트는 pre-flight-check.sh처럼 "호출 시점의 현재 저장소"를 검증하는 범용
# 도구가 아니라 항상 자기 자신이 속한 dotfiles 저장소의 contexts/만 대상으로 하는
# 전용 린터다. init_repo_root()(호출 CWD 기준 git rev-parse)를 쓰면 dotfiles 밖에서
# 호출됐을 때 REPO_ROOT가 엉뚱한 곳을 가리켜 대상 자체가 사라지므로, CWD와 무관하게
# 스크립트 자신의 물리적 위치로 REPO_ROOT를 고정한다(generate-context-index.sh와 동일 패턴).
REPO_ROOT=$(cd "$PROMPT_LINT_SCRIPT_DIR/../.." && pwd)

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
    echo "[WARNING] 공통 자가 비판 절차 SSOT 선언 파일을 찾지 못했습니다."
    return
  fi

  local corefile skill_dir declared_line declared actual own_prefix ref_md ref_names
  for corefile in "${core_files[@]}"; do
    [ -z "$corefile" ] && continue
    skill_dir=$(dirname "$(dirname "$corefile")")
    # grep 무매치(exit 1) 시 pipefail에 의한 스크립트 중단 방지를 위해 빈 문자열로 흡수
    own_prefix=$(basename "$corefile" | grep -oE '^[0-9]{3}' || true)

    declared_line=$(grep "공통 자가 비판 절차" "$corefile" || true)
    declared=$(grep -oE '\([0-9]{3}(, [0-9]{3})*\)' <<<"$declared_line" | tr -d '()' | tr -d ' ' | tr ',' '\n' | sort -u || true)

    # find -printf 는 GNU 전용이라 macOS(BSD find)에서는 아무것도 출력하지 못한다.
    # 그런데 2>/dev/null 로 그 에러가 묻혀 actual 이 빈 값이 되고, 결국 declared 와
    # 어긋나 "SSOT 모듈 목록 불일치"라는 없는 결함을 신고하며 커밋을 막는다.
    # references/ 바로 아래만 보므로(기존 -maxdepth 1 과 동등) 셸 글롭으로 대체한다.
    # 참고: 기존의 -path "$CONTEXTS_DIR/.*" -prune 은 깊이 1에서는 매치될 수 없어 무의미했다.
    ref_names=()
    for ref_md in "$skill_dir"/references/*.md; do
      [ -f "$ref_md" ] || continue
      ref_names+=("${ref_md##*/}")
    done
    actual=$(printf '%s\n' "${ref_names[@]:-}" |
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
  done < <(grep -rHoE 'contexts/[a-z0-9-]+/(references/[0-9]{3}-[a-z0-9_-]+\.md|SKILL\.md|role\.[a-z0-9_-]+\.md|(scripts|tests)/([a-z0-9_-]+/)?[a-z0-9_-]+\.(sh|py)|evals/[a-z0-9_-]+/[a-z0-9_-]+\.(sh|tsv))' "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".*" 2>/dev/null | sort -u || true)

  # SKILL.md 라우팅 테이블은 절대 경로가 아니라 자신의 스킬 루트 기준 상대 경로
  # (예: "references/020-xxx.md")를 쓴다. 위 절대 패턴 검사는 이 형태를 잡지 못하므로
  # 스킬 루트(SKILL.md의 위치, references/*.md는 한 단계 상위) 기준으로 별도 검사한다.
  local rline rest stripped skill_dir r
  while IFS= read -r rline; do
    [ -z "$rline" ] && continue
    f="${rline%%:*}"
    rest="${rline#*:}"
    # 이미 위에서 절대 경로(contexts/스킬/references/...)로 검사된 매치는 제외한다.
    stripped=$(sed -E 's#contexts/[a-z0-9-]+/references/[0-9]{3}-[a-z0-9_-]+\.md##g' <<<"$rest")
    skill_dir=$(dirname "$f")
    [ "$(basename "$skill_dir")" = "references" ] && skill_dir=$(dirname "$skill_dir")
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      [ -f "$skill_dir/$r" ] || {
        echo "❌ [ERROR] 깨진 스킬-상대 참조 링크: $f -> $r" >&2
        EXIT_CODE=1
      }
    done < <(grep -oE 'references/[0-9]{3}-[a-z0-9_-]+\.md' <<<"$stripped" || true)
  done < <(grep -rHE 'references/[0-9]{3}-[a-z0-9_-]+\.md' "$CONTEXTS_DIR"/*/SKILL.md "$CONTEXTS_DIR"/*/references/*.md 2>/dev/null | sort -u || true)

  log_info "[INFO] 참조 링크 검사 완료."
}

# -----------------------------------------------------------------------------
# 3. 라우팅 테이블 고아 파일 탐지 (SKILL.md에 언급되지 않은 reference 파일)
# -----------------------------------------------------------------------------
check_orphaned_files() {
  log_info "--- Step: Orphaned Reference File Detection ---"
  local skill_dir skill_md fname f
  for skill_dir in "$CONTEXTS_DIR"/*/; do
    skill_md="${skill_dir}SKILL.md"
    [ -f "$skill_md" ] || continue
    [ -d "${skill_dir}references" ] || continue
    for f in "${skill_dir}references"/*.md; do
      [ -f "$f" ] || continue
      fname=$(basename "$f")
      grep -Fq "$fname" "$skill_md" || echo "[WARNING] 고아 후보(라우팅 테이블에 없음): $f"
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
  # pipefail 이 그것을 파이프라인 결과로 채택해 "찾았는데 못 찾음"으로 뒤집힌다.
  if [ -s "$names_file" ]; then
    grep -rhoFf "$names_file" --include="*.md" --exclude-dir=".*" --exclude="README.md" "$CONTEXTS_DIR" 2>/dev/null |
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
# 4. CORE EXCEPTION HOOK 마커 무결성 검사 (블랑켓 무효화 금지 + 룰 실재성 대조)
# -----------------------------------------------------------------------------
check_exception_hook_integrity() {
  log_info "--- Step: Exception Hook Marker Integrity ---"
  local base_agents="$CONTEXTS_DIR/base.AGENTS.md"
  [ -f "$base_agents" ] || {
    log_info "[INFO] 예외 마커 검사 건너뜀 (contexts/base.AGENTS.md 없음)."
    return
  }

  # base.AGENTS.md에 실재하는 조항 이름 집합 추출 (Documented Clause Existence와 동일 패턴)
  local names_file
  names_file=$(mktemp)
  sed -nE 's/^[[:space:]]*[-*][[:space:]]+\*\*(\[[^]]+\][[:space:]]*)?([A-Za-z][A-Za-z0-9 &'"'"'\/-]*[A-Za-z0-9])[[:space:]]*(\([^)]*\))?[[:space:]]*:\*\*.*/\2/p' \
    "$base_agents" | sort -u >"$names_file"

  # "전체 무효화" 류 블랑켓(범위 미특정) 선언 금지 문구
  local blanket_pattern='전체 무효화|전면 무효화|FULL RULE OVERRIDE|모든 룰'
  local skill_md marker_line blanket_hit block item_line item_name

  while IFS= read -r skill_md; do
    [ -f "$skill_md" ] || continue
    grep -q "EXCEPTION APPLIED" "$skill_md" || continue

    marker_line=$(grep "EXCEPTION APPLIED" "$skill_md" || true)
    blanket_hit=$(grep -E "$blanket_pattern" <<<"$marker_line" || true)
    if [ -n "$blanket_hit" ]; then
      echo "❌ [ERROR] 범위를 특정하지 않은 예외 선언(블랑켓 무효화): $skill_md" >&2
      echo "    완화 대상 룰을 base.AGENTS.md CORE EXCEPTION HOOK 포맷대로 개별 열거하십시오." >&2
      EXIT_CODE=1
      continue
    fi

    # 마커가 시작된 블록쿼트(연속된 '>' 라인) 안에서 근거 불릿(- **이름**)만 추출
    block=$(awk '
      /EXCEPTION APPLIED/ { infound=1 }
      infound { if ($0 ~ /^>/) { print; next } else { exit } }
    ' "$skill_md")

    while IFS= read -r item_line; do
      [ -z "$item_line" ] && continue
      item_name=$(sed -E 's/^>[[:space:]]*-[[:space:]]+\*\*([^*]+)\*\*.*/\1/' <<<"$item_line")
      [ -z "$item_name" ] && continue
      grep -qxF -- "$item_name" "$names_file" || {
        echo "❌ [ERROR] 예외 대상으로 열거된 룰이 base.AGENTS.md에 실재하지 않음: $skill_md" >&2
        echo "    선언된 이름: '$item_name' (개명·삭제됐거나 오타일 수 있습니다)" >&2
        EXIT_CODE=1
      }
    done < <(grep -E '^>[[:space:]]*-[[:space:]]+\*\*' <<<"$block" || true)
  done < <(find "$CONTEXTS_DIR" -path "$CONTEXTS_DIR/.*" -prune -o -name "SKILL.md" -print)

  rm -f "$names_file"
  log_info "[INFO] 예외 마커 무결성 검사 완료."
}

# -----------------------------------------------------------------------------
# 5. 파일 크기 제약 (150줄) 검사
# -----------------------------------------------------------------------------
check_file_size() {
  log_info "--- Step: File Size Constraint (rule=150 / library=250 lines) ---"
  find "$CONTEXTS_DIR" -path "$CONTEXTS_DIR/.*" -prune -o -path "*/references/*.md" -print0 | xargs -0 wc -l 2>/dev/null | awk '
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
# 6. 크로스 클라우드/스킬 벤더 용어 오염 검사 (고정밀 패턴만)
# -----------------------------------------------------------------------------
check_vendor_leakage() {
  log_info "--- Step: Cross-Vendor Terminology Leakage ---"
  local hit

  # azurecr.io는 예시 코드에 하드코딩된 벤더 종속 레지스트리다. 예전엔 azure/ 스킬 안에서만
  # 허용하는 예외를 뒀는데, 그 스킬을 지운 뒤로는 어느 룰북에도 등장할 이유가 없다 —
  # 예외를 없애 검사 범위를 코퍼스 전체로 넓힌다.
  hit=$(grep -rl "azurecr\.io" "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".*" 2>/dev/null || true)
  [ -n "$hit" ] && {
    echo "❌ [ERROR] 룰북에서 azurecr.io 발견:" >&2
    echo "    ${hit//$'\n'/$'\n    '}" >&2
    EXIT_CODE=1
  }

  # "IAM/RBAC" 병기는 aws 폴더에서는 부정확한 표현 (AWS는 IAM/RBAC를 공식 병기하지 않음)
  hit=$(grep -rl "IAM/RBAC" "$CONTEXTS_DIR/aws" --include="*.md" --exclude-dir=".*" 2>/dev/null || true)
  [ -n "$hit" ] && {
    echo "❌ [ERROR] aws 폴더에서 'IAM/RBAC' 병기 발견 (Azure 전용 표현):" >&2
    echo "    ${hit//$'\n'/$'\n    '}" >&2
    EXIT_CODE=1
  }

  log_info "[INFO] 벤더 용어 오염 검사 완료."
}

# -----------------------------------------------------------------------------
# 7. 코드펜스 짝 검사
# -----------------------------------------------------------------------------
check_code_fences() {
  log_info "--- Step: Code Fence Balance ---"
  local unclosed
  unclosed=$(find "$CONTEXTS_DIR" -path "$CONTEXTS_DIR/.*" -prune -o -name "*.md" -print0 | xargs -0 awk '
    BEGIN { fail = 0; }
    FNR == 1 {
      if (count % 2 != 0) {
        print current_file
        fail = 1
      }
      current_file = FILENAME
      count = 0
    }
    # 들여쓴 펜스(리스트 항목 안의 코드 블록 등)도 센다. ^``` 만 보면 열림/닫힘 중 한쪽만
    # 들여쓴 문서에서 짝이 안 맞는데도 조용히 통과한다. 현재 코퍼스에는 들여쓴 펜스가
    # 20건 있고, 이 패턴으로 바꿔도 판정 결과는 그대로 깨끗함을 실측 확인했다.
    # (블록쿼트 안의 "> ```" 은 종전과 동일하게 대상이 아니다 — 앞이 공백이 아니라 ">" 라
    #  이 패턴에 걸리지 않는다.)
    /^[[:space:]]*```/ { count++ }
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
# 8. Halt & Clarify / Hard Block 등급 휴리스틱 (경고 전용)
# -----------------------------------------------------------------------------
check_severity_tag_heuristic() {
  log_info "--- Step: Halt & Clarify vs Hard Block Severity Heuristic (Warning Only) ---"
  # 보안 취약점 등 고위험 키워드가 포함된 경우 Hard Block 등급 상향 필요성 알림
  local risk_keywords='privileged|hostNetwork|평문|자격 증명|시크릿.*유출|credential|secret.*leak|0\.0\.0\.0/0|CVE|readOnlyRootFilesystem'
  local hits
  hits=$(grep -rHE "$risk_keywords" "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".*" 2>/dev/null | grep "Halt & Clarify" || true)
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
# 8b. MUST 로 태깅됐지만 본문이 선호를 서술하는 조항 탐지 (경고 전용)
# -----------------------------------------------------------------------------
check_prefer_language_tagged_must() {
  log_info "--- Step: Preference Wording Tagged as MUST (Warning Only) ---"
  # 본문에 선호 표현("가급적", "우선 탐색" 등) 포함 시 MUST 대신 PREFER 사용 안내
  local prefer_words='최우선으로 (제안|탐색|시도|고려)|최우선 (제안|탐색)|가급적|우선 탐색|권장합니다|권장하십시오'
  local hits
  hits=$(grep -rHE '^\s*[-*]\s+\*\*\[MUST\]' "$CONTEXTS_DIR" --include="*.md" --exclude-dir=".*" 2>/dev/null | grep -E "$prefer_words" || true)
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
# 9. 크로스 스킬 개념 중복 후보 탐지 (경고 전용, 자동 수정 없음)

# -----------------------------------------------------------------------------
# 10. aws/azure 미러링 대칭성 검사 (Warning Only)

# -----------------------------------------------------------------------------
# 11. contexts/INDEX.md 최신성 검사 (Warning Only)
# -----------------------------------------------------------------------------
check_index_freshness() {
  log_info "--- Step: contexts/INDEX.md Freshness (Warning Only) ---"
  local index_file="$CONTEXTS_DIR/INDEX.md"
  local generator="$REPO_ROOT/bin/utils/generate-context-index.sh"

  # 온보딩용 색인이라 신규/실험 저장소에는 아직 없을 수 있다. 없으면 강제하지 않고
  # 건너뛴다(check_documented_clause_existence 의 README 부재 처리와 동일한 관용구).
  [ -f "$index_file" ] || {
    log_info "[INFO] contexts/INDEX.md 없음 — 색인 최신성 검사 건너뜀."
    return
  }
  [ -f "$generator" ] || {
    log_info "[INFO] 색인 생성기($generator)를 찾지 못해 검사 건너뜀."
    return
  }

  local tmp
  tmp=$(mktemp)
  if ! bash "$generator" >"$tmp" 2>/dev/null; then
    echo "[WARNING] 색인 생성기 실행 실패 — contexts/INDEX.md 최신성을 확인하지 못했습니다."
    rm -f "$tmp"
    return
  fi

  if ! diff -q "$index_file" "$tmp" >/dev/null 2>&1; then
    echo "[WARNING] contexts/INDEX.md 가 SKILL.md 라우팅 테이블과 어긋납니다:"
    # 맥락 줄도 반드시 echo + "[WARNING]" 접두사여야 한다(이 파일 상단 [출력 규약] 참조).
    # log_info 로 두면 QUIET=1 이 기본인 훅·run-suite·CI 경로에서 "어긋났다"만 뜨고 정작
    # 고치는 방법은 한 번도 출력되지 않는다.
    echo "[WARNING]     'bash bin/utils/generate-context-index.sh > contexts/INDEX.md' 로 재생성하십시오."
  fi
  rm -f "$tmp"
  log_info "[INFO] 색인 최신성 검사 완료."
}

# -----------------------------------------------------------------------------
# 12. README 스킬 표의 모듈 수 최신성 검사 (Warning Only)
# -----------------------------------------------------------------------------
# 이 저장소의 문서는 스킬을 .archive 로 옮기거나 룰북을 통폐합해도 개수만 그대로 남는
# 드리프트가 실제로 있었다(실측: 활성 스킬이 9개가 된 뒤에도 문서·주석 5곳이 "12개"를,
# README 표가 Dotfiles "10개(000~060)"를 주장 — 실제는 6개(010~060)였고 000 번 파일은
# 존재한 적이 없다). 산문 쪽 숫자는 개수 비의존 표현으로 걷어냈지만 표는 숫자가 형식상
# 불가피하므로, 그 축만 기계적으로 대조한다.
#
# README 는 사람이 쓰는 문서라 하드 블록이 아니라 경고로 둔다(check_index_freshness 와
# 동일한 등급). CONTEXTS_DIR 이 아니라 저장소 루트를 보는 유일한 검사다.
check_readme_skill_counts() {
  log_info "--- Step: README 스킬 표 모듈 수 (Warning Only) ---"
  local readme="$REPO_ROOT/README.md"
  [ -f "$readme" ] || {
    log_info "[INFO] README.md 없음 — 스킬 표 검사 건너뜀."
    return
  }

  local line skill claim actual
  # 정규식 안의 백틱은 마크다운 인라인 코드 표기라 리터럴이다(셸 명령 치환이 아니므로
  # 홑따옴표가 맞다). 루프 안팎의 grep 둘 다 해당하므로 while 전체에 한 번만 붙인다.
  # shellcheck disable=SC2016
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    skill=$(grep -oE '\(`[a-z0-9-]+/`\)' <<<"$line" | tr -d '(`)/' | head -1)
    claim=$(grep -oE '\| [0-9]+개' <<<"$line" | grep -oE '[0-9]+' | head -1)
    [ -n "$skill" ] && [ -n "$claim" ] || continue
    # 표에 있지만 이미 .archive 로 옮겨진 스킬은 references 디렉토리 자체가 없다.
    # 그 경우는 개수 불일치가 아니라 표에 남은 항목 자체가 문제이므로 따로 알린다.
    if [ ! -d "$CONTEXTS_DIR/$skill/references" ]; then
      echo "[WARNING] README 스킬 표에 있는 '$skill' 의 references 디렉토리가 없습니다(아카이브됐거나 이름이 바뀜)."
      continue
    fi
    actual=$(find "$CONTEXTS_DIR/$skill/references" -maxdepth 1 -name '*.md' | wc -l)
    if [ "$claim" -ne "$actual" ]; then
      echo "[WARNING] README 스킬 표의 모듈 수가 실제와 다릅니다: $skill — 표 ${claim}개 / 실제 ${actual}개"
      echo "[WARNING]     $readme 의 해당 행을 실제 개수와 번호 범위에 맞추십시오."
    fi
  done < <(grep -E '^\|[^|]*\(`[a-z0-9-]+/`\)' "$readme" || true)

  log_info "[INFO] README 스킬 표 검사 완료."
}

# -----------------------------------------------------------------------------
# 14. contexts/ 스캔의 숨김 디렉토리 제외 일관성
# -----------------------------------------------------------------------------
# `contexts/` 아래 점으로 시작하는 디렉토리(현재는 테스트 전용 라이브러리 `.shared` 하나)는
# "어떤 소비자도 취급하지 않는다"가 이 코퍼스의 규약이다. 그런데 그 규약은 자동으로 지켜지지
# 않는다 — 셸 glob(`"$CONTEXTS_DIR"/*/`)은 dotglob 없이 숨김 디렉토리를 건너뛰지만,
# `find` 와 `ansible.builtin.find` 는 그렇지 않다. 특히 후자는 `hidden: false` 가 숨김
# "파일"만 거르고 숨김 "디렉토리" 안으로는 그대로 recurse 한다(ansible-core 2.19.11 실측).
#
# 그 차이 때문에 같은 규약을 여러 곳에 손으로 넣다가 두 곳을 빠뜨렸고, 둘 다 실제 피해로
# 이어졌다(당시엔 폐기 스킬 보관소 `.archive` 도 있었다 — 지금은 지웠고 내용은 git 히스토리에
# 남아 있다): 폐기 스킬의 스크립트가 매 setup 마다 사용자 PATH 에 링크됐고(ansible ai_agent
# 롤), 폐기 룰북이 근거 기록의 스킬 보정 후보에 섞여 정상 기록을 막거나 존재하지 않는
# 룰을 SUCCESS 로 남겼다(record-provenance.sh). 보관소를 지웠다고 규약이 없어지지는 않는다 —
# `.shared` 가 그대로 있고, 숨김 디렉토리는 언제든 다시 생긴다.
#
# 문서 규칙(010-core.md 의 Sibling Sweep)만으로 두지 않고 여기서 기계적으로 대조한다 —
# 050-rule-provenance-standard.md 의 자가 비판 기준("스크립트로 pass/fail 판정이 가능한
# 조항인데 문서 규칙에만 머물러 있지 않은가")이 요구하는 바다.
#
# 판정은 오탐 0을 우선해 좁게 잡는다:
#  (a) 셸: 명령 위치의 `find` 가 contexts "루트"를 대상으로 잡는 경우만. 특정 스킬 하위를
#      지목하는 `find "$CONTEXTS_DIR/$skill/references"` 는 구조적으로 숨김 디렉토리에 닿을
#      수 없으므로 대상이 아니다. 제외 토큰(-prune / ! -path / -not -path / --exclude-dir)이
#      하나라도 있으면 통과.
#  (b) ansible: `ansible.builtin.find` 로 contexts 를 `recurse: true` 스캔하는 파일은
#      경로 가드 토큰 `/contexts/.` 를 코드에 갖고 있어야 한다. 제외 조건이 find 태스크가
#      아니라 그 결과를 loop 하는 별도 태스크의 when: 에 붙는 구조라, 태스크 블록 단위가
#      아니라 파일 단위로 본다. 주석은 걷어내고 본문만 대조한다 — 주석에 토큰이 스쳐도
#      통과시키면 그 순간 게이트가 무력화된다(test-coverage-check.sh 의 run.sh 등록 검사와
#      동일한 사유).
# 두 판정 모두 위 두 결함의 수정 직전 커밋 상태에서 실제로 검출됨을 확인했다.
check_archive_scope_consistency() {
  log_info "--- Step: contexts/ 스캔의 숨김 디렉토리 제외 일관성 ---"
  local f hit lineno body rel code

  # (a) 셸 find
  while IFS= read -r -d '' f; do
    rel="${f#"$REPO_ROOT"/}"
    # 홑따옴표가 맞다: 셸이 아니라 grep 이 해석할 정규식이다.
    # shellcheck disable=SC2016
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      lineno="${hit%%:*}"
      body="${hit#*:}"
      grep -qE '(-prune|! -path|-not -path|--exclude-dir)' <<<"$body" && continue
      echo "❌ [ERROR] contexts/ 루트를 훑는 find 에 숨김 디렉토리 제외가 없습니다: $rel:$lineno" >&2
      echo "    $(sed -E 's/^[[:space:]]+//' <<<"$body")" >&2
      echo "    -> .shared 등 숨김 디렉토리가 결과에 섞입니다. -prune 또는 ! -path \"*/contexts/.*\" 를 추가하십시오." >&2
      EXIT_CODE=1
    done < <(grep -nE '(^|[;|(&]|\$\()[[:space:]]*find[[:space:]]+("?\$\{?CONTEXTS_DIR\}?"?|"[^"]*/contexts")[[:space:]]' "$f" || true)
  done < <(find "$REPO_ROOT/bin" "$REPO_ROOT/stow" "$REPO_ROOT/.github" \
    -type f \( -name '*.sh' -o -path '*/.githooks/*' \) -print0 2>/dev/null)

  # (b) ansible.builtin.find
  while IFS= read -r -d '' f; do
    rel="${f#"$REPO_ROOT"/}"
    code=$(grep -vE '^[[:space:]]*#' "$f" || true)
    grep -q 'ansible.builtin.find' <<<"$code" || continue
    grep -q 'contexts' <<<"$code" || continue
    grep -qE 'recurse:[[:space:]]*true' <<<"$code" || continue
    grep -qF '/contexts/.' <<<"$code" && continue
    echo "❌ [ERROR] contexts/ 를 recurse 스캔하는 ansible find 에 경로 가드가 없습니다: $rel" >&2
    echo "    -> hidden 기본값은 숨김 디렉토리를 걸러 주지 않습니다. 결과를 소비하는 태스크의" >&2
    echo "       when: 에 \"'/contexts/.' not in item.path\" 를 추가하십시오." >&2
    EXIT_CODE=1
  done < <(find "$REPO_ROOT/ansible" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)

  log_info "[INFO] contexts/ 스캔 제외 일관성 검사 완료."
}

# -----------------------------------------------------------------------------
# 15. 끊긴 파일 참조 검사 (주석·문서가 가리키는 저장소 내 경로가 실존하는가)
# -----------------------------------------------------------------------------
# 이 저장소의 주석은 밀도가 높아 근거(rationale)와 사실(fact)을 함께 담는다. 근거는 낡지
# 않지만 사실은 낡는다 — 특히 "이 함정을 X.sh 에서 이미 고쳤다", "Y.sh 가 이걸 공유한다"
# 처럼 다른 파일을 지목하는 문장은 그 파일이 옮겨지거나 지워지면 곧바로 거짓이 된다.
# 실제로 tf-fixture-lib.sh 를 인라인했을 때 그 파일을 가리키던 참조가 6곳 남았고, 손으로
# 훑어 고친 뒤에도 ansible 롤에 1곳이 더 남아 있었다(이 검사가 그것을 잡아냈다).
#
# 낡은 참조는 조용하다. 코드가 아니라 주석이라 아무것도 깨뜨리지 않고, 다음에 읽는 사람
# (사람이든 에이전트든)에게만 없는 파일을 찾게 만든다. 기계적으로 대조한다.
#
# 판정은 오탐 0을 우선해 좁게 잡는다:
#  (a) 저장소 최상위 디렉토리(bin/contexts/stow/ansible)로 "시작하는" 경로만 본다. 앞에
#      변수나 따옴표가 붙은 것($FIXTURE_REPO/contexts/...), URL(//host/install.sh),
#      가상의 예시 경로(src/main.py, sub/check.sh)가 구조적으로 배제된다.
#  (b) tests/ 하위는 스캔하지 않는다. 회귀 테스트는 합성 트리(contexts/demo,
#      contexts/fake, contexts/probe 등)를 만드는 것이 본업이라 존재하지 않는 경로를
#      정당하게 쓴다 — 실측에서 오탐 12건 중 11건이 여기였다.
#  (c) 참조된 "디렉토리"가 실존할 때만 판정한다. 디렉토리부터 없으면 문서 템플릿의
#      자리표시자(contexts/example-skill/custom-role.md)로 보고 넘긴다.
#  (d) 대상은 `git ls-files` 가 돌려주는 "이 저장소가 추적하는 파일"뿐이다. find 로 훑으면
#      저장소 안에 굴러들어온 사본까지 코퍼스로 취급한다 — 실제로 이 검사의 회귀 테스트가
#      그렇게 깨졌다. 케이스 디렉토리는 prompt-lint.sh 자신을 복사해 넣는데(격리 실행을
#      위해 필요하다), 그 사본의 주석이 지목하는 bin/lib/tool-probe.sh 같은 파일은 그
#      최소 코퍼스에 없으므로 전부 끊긴 참조로 잡혔다. 추적 대상으로 한정하면 사본은
#      애초에 코퍼스가 아니게 되어 이 혼동이 구조적으로 사라진다.
# 위 넷을 적용해 현재 코퍼스 오탐 0, 그리고 ansible 수정 직전 커밋에서 실제 검출을 확인했다.
check_dangling_file_references() {
  log_info "--- Step: Dangling File Reference ---"
  local f ref dir
  # 홑따옴표가 맞다: 셸이 아니라 grep 이 해석할 정규식이다.
  # shellcheck disable=SC2016
  local pat='(^|[^A-Za-z0-9_./$"{-])(bin|contexts|stow|ansible)/[A-Za-z0-9_./-]+\.(sh|py|md|yml|yaml)'

  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    log_info "[INFO] git 저장소가 아니어서 끊긴 참조 검사를 건너뜁니다."
    return 0
  fi

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in */tests/*) continue ;; esac
    [ -f "$REPO_ROOT/$f" ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ -e "$REPO_ROOT/$ref" ] && continue
      dir=$(dirname "$ref")
      [ -d "$REPO_ROOT/$dir" ] || continue
      echo "❌ [ERROR] 존재하지 않는 파일을 가리키는 참조: $f -> $ref" >&2
      echo "    -> 그 파일이 옮겨졌거나 지워졌습니다. 현재 위치로 고치거나 문장을 지우십시오." >&2
      EXIT_CODE=1
    done < <(grep -ohE "$pat" "$REPO_ROOT/$f" 2>/dev/null | sed -E 's#^[^A-Za-z0-9_.]##' | sort -u || true)
  done < <(git -C "$REPO_ROOT" ls-files -- 'bin/*' 'contexts/*' 'stow/*' 'ansible/*' 2>/dev/null |
    grep -E '\.(sh|md|yml|yaml)$' || true)

  log_info "[INFO] 끊긴 파일 참조 검사 완료."
}

# -----------------------------------------------------------------------------
# 16. [Good] Dockerfile 예제가 저장소 자신의 하드 게이트를 통과하는가
# -----------------------------------------------------------------------------
# 룰북의 few-shot 예제는 설명이 아니라 에이전트가 그대로 베끼는 템플릿이다. 그래서
# [Good] 예제가 이 저장소의 커밋 게이트에 걸리는 코드를 시연하면, 룰을 따른 결과물이
# 그 룰을 강제하는 파이프라인에 막히는 모순이 생긴다.
#
# 실제로 그 상태였다: 010-containers-core.md 의 [Good] Dockerfile 이 최종 스테이지에
# USER 를 두지 않아 container-hardening-gate.sh(trivy DS-0002)에 exit 1 로 걸렸고,
# 베이스 이미지에 태그가 없어 DS-0001(:latest)까지 났다. 정작 태그 고정은 같은 파일
# 8줄 위의 [MUST] Pinned Versions 가, 비루트는 020 의 [MUST] Non-Root by Default 가
# 요구하던 것이다. 사람이 두 문서를 나란히 놓고 대조해야만 보이던 종류라 기계로 옮긴다.
#
# 검사 축은 둘이다: container-hardening-gate.sh(비루트, trivy DS-0002)와 hadolint(핀
# 고정, DL3006/DL3007). 위 두 [MUST] 가 각각 이 둘에 대응한다.
#
# 완결된 예제만 태운다("FROM 이 있는가"). 이 코퍼스에는 USER 지시어 하나만 보여 주는
# 의도적 부분 스니펫이 있는데, 그건 Dockerfile 로서 미완성인 게 정상이라 게이트에
# 넣으면 고칠 수 없는 오탐(DL3061 류)이 된다. [Bad] 예제도 당연히 제외한다 — 위반을
# 시연하는 것이 그 예제의 목적이다.
check_good_dockerfile_examples() {
  log_info "--- Step: [Good] Dockerfile 예제의 하드 게이트 준수 ---"
  local gate="$PROMPT_LINT_SCRIPT_DIR/container-hardening-gate.sh"
  if [ ! -f "$gate" ]; then
    log_info "[INFO] container-hardening-gate.sh 를 찾지 못해 건너뜁니다."
    return
  fi

  local tmpdir md line trimmed label inany indocker buf start lineno n=0 out
  tmpdir=$(mktemp -d)
  while IFS= read -r md; do
    label=""
    inany=0
    indocker=0
    buf=""
    start=0
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))
      trimmed="${line#"${line%%[![:space:]]*}"}"
      if [ "$inany" -eq 1 ]; then
        case "$trimmed" in
        '```'*)
          inany=0
          if [ "$indocker" -eq 1 ]; then
            indocker=0
            grep -q '^[[:space:]]*FROM[[:space:]]' <<<"$buf" || continue
            n=$((n + 1))
            out="$tmpdir/$n.Dockerfile"
            printf '%s' "$buf" >"$out"
            if ! bash "$gate" "$out" >"$tmpdir/out.$n" 2>&1; then
              echo "❌ [ERROR] [Good] Dockerfile 예제가 컨테이너 하드닝 게이트에 걸립니다: ${md#"$REPO_ROOT"/}:$start" >&2
              # 게이트는 추출된 임시 파일 경로를 그대로 찍는다. 그대로 두면 어느 예제인지
              # 알아볼 수 없으므로 원본 위치로 되돌린다(pre-commit 훅의 trufflehog 출력
              # 정리와 동일한 관용구).
              sed -e "s#$out#${md#"$REPO_ROOT"/}:$start#g" -e 's/^/    /' "$tmpdir/out.$n" >&2
              echo "    -> 이 예제를 그대로 따르면 커밋이 막힙니다. 예제를 고치거나, 규칙 쪽이 현실과 다르면 규칙을 고치십시오." >&2
              EXIT_CODE=1
            fi
            # 위 게이트는 DS-0002(비루트) 한 축만 하드 블록한다. 핀 고정 축은 hadolint
            # DL3006/DL3007 이 담당하며, 저장소는 이미 실제 Dockerfile 에 같은 잣대를
            # 적용하고 있다(pfc-quality-checks.sh 의 validate_docker). 예제에만 느슨한
            # 기준을 두면 [MUST] Pinned Versions 를 정면으로 어긴 예제가 그대로 통과한다
            # (실측: [Good] 예제를 FROM node:latest 로 되돌린 뮤테이션이 게이트만으로는
            # 검출되지 않았다). `:nonroot` 같은 역할 태그는 DL3007 대상이 아니므로
            # distroless 예제는 이 검사를 그대로 통과한다(실측).
            if has_tool hadolint; then
              if ! hadolint "$out" >"$tmpdir/hado.$n" 2>&1; then
                echo "❌ [ERROR] [Good] Dockerfile 예제가 hadolint 에 걸립니다: ${md#"$REPO_ROOT"/}:$start" >&2
                sed -e "s#$out#${md#"$REPO_ROOT"/}:$start#g" -e 's/^/    /' "$tmpdir/hado.$n" >&2
                echo "    -> 이 예제를 그대로 따르면 커밋이 막힙니다. 예제를 고치거나, 규칙 쪽이 현실과 다르면 규칙을 고치십시오." >&2
                EXIT_CODE=1
              fi
            else
              log_info "[INFO] hadolint 가 없어 [Good] Dockerfile 예제의 핀 고정 검사를 건너뜁니다."
            fi
          fi
          continue
          ;;
        esac
        [ "$indocker" -eq 1 ] && buf="${buf}${line}"$'\n'
        continue
      fi
      case "$trimmed" in
      '```dockerfile'*)
        inany=1
        indocker=1
        buf=""
        start=$lineno
        ;;
      '```'*)
        inany=1
        indocker=0
        ;;
      '[Good]'*) label="Good" ;;
      '[Bad]'*) label="Bad" ;;
      esac
      # 여는 펜스를 만난 시점의 라벨만 유효하다. [Bad] 블록이면 아예 수집하지 않는다.
      if [ "$indocker" -eq 1 ] && [ "$label" != "Good" ]; then
        indocker=0
      fi
    done <"$md"
  done < <(find "$CONTEXTS_DIR" -path "$CONTEXTS_DIR/.*" -prune -o -name "*.md" -print)
  rm -rf "$tmpdir"
  log_info "[INFO] [Good] Dockerfile 예제 검사 완료(대상 ${n}건)."
}

main() {
  check_ssot_module_lists
  check_reference_links
  check_orphaned_files
  check_documented_clause_existence
  check_exception_hook_integrity
  check_file_size
  check_vendor_leakage
  check_code_fences
  check_severity_tag_heuristic
  check_prefer_language_tagged_must
  check_index_freshness
  check_readme_skill_counts
  check_archive_scope_consistency
  check_dangling_file_references
  check_good_dockerfile_examples

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
