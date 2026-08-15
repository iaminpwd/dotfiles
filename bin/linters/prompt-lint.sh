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
