#!/usr/bin/env bash
# prompt-lint.sh - Dotfiles Prompt Corpus Consistency Linter
#
# 프롬프트 원본(.md) 자가 검증용 스크립트
# (타 프로젝트 인프라 검증용이 아니므로 preflight/ 위임 경로 밖에 배치)
#
# ERROR: 명확한 결함(깨진 참조, 코드펜스, 숨김 contexts 범위, dangling path, routing 정합성) -> 종료 코드 1
# WARNING: 자동 수정하지 않는 드리프트 후보(orphan reference, INDEX/README 불일치) -> 통과는 시키되 눈에 띄게 출력
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
set -euo pipefail

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
      grep -Fq "$fname" "$skill_md" || echo "[WARNING] [ADVISORY] 고아 후보(라우팅 테이블에 없음): $f"
    done
  done
  log_info "[INFO] 고아 파일 검사 완료."
}

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
check_index_freshness() {
  log_info "--- Step: contexts/INDEX.md Freshness (Warning Only) ---"
  local index_file="$CONTEXTS_DIR/INDEX.md"
  local generator="$REPO_ROOT/bin/utils/generate-context-index.sh"

  # 온보딩용 색인이라 신규/실험 저장소에는 아직 없을 수 있다. 없으면 강제하지 않고
  # 건너뛴다(README가 없는 저장소와 동일하게 선택적으로).
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
    skill=$(grep -oE '\(`[a-z0-9-]+/`\)' <<<"$line" | tr -d '(`)/' | head -1 || true)
    claim=$(grep -oE '\| [0-9]+개' <<<"$line" | grep -oE '[0-9]+' | head -1 || true)
    [ -n "$skill" ] || continue
    # reference를 모두 SKILL.md로 통합한 스킬은 숫자 개수 자체가 없을 수 있다.
    # 숫자 claim이 없는 행은 이 검사의 대상이 아니며, set -e로 린터를 조용히 죽이지 않는다.
    [ -n "$claim" ] || continue
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
# `contexts/` 아래 점으로 시작하는 디렉토리는
# "어떤 소비자도 취급하지 않는다"가 이 코퍼스의 규약이다. 그런데 그 규약은 자동으로 지켜지지
# 않는다 — 셸 glob(`"$CONTEXTS_DIR"/*/`)은 dotglob 없이 숨김 디렉토리를 건너뛰지만,
# `find` 와 `ansible.builtin.find` 는 그렇지 않다. 특히 후자는 `hidden: false` 가 숨김
# "파일"만 거르고 숨김 "디렉토리" 안으로는 그대로 recurse 한다(ansible-core 2.19.11 실측).
#
# 그 차이 때문에 같은 규약을 여러 곳에 손으로 넣다가 두 곳을 빠뜨렸고, 둘 다 실제 피해로
# 이어졌다(당시엔 폐기 스킬 보관소 `.archive` 도 있었다 — 지금은 지웠고 내용은 git 히스토리에
# 남아 있다): 폐기 스킬의 스크립트가 매 setup 마다 사용자 PATH 에 링크됐고(ansible ai_agent
# 롤), 폐기 룰북이 근거 기록의 스킬 보정 후보에 섞여 정상 기록을 막거나 존재하지 않는
# 룰을 SUCCESS 로 남겼다(record-provenance.sh). 보관소와 공유 테스트 라이브러리를 contexts 밖으로 옮겼어도 규약이 없어지지는 않는다 —
# 숨김 디렉토리는 언제든 다시 생길 수 있다.
#
# 숨김 디렉토리 제외 계약은 실행 경로마다 반복되므로 문서 규칙이 아니라 여기서
# 기계적으로 대조한다.
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
      echo "    -> 숨김 contexts 디렉토리가 결과에 섞입니다. -prune 또는 ! -path \"*/contexts/.*\" 를 추가하십시오." >&2
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
#      저장소 안에 굴러들어온 사본까지 코퍼스로 취급한다. 회귀 테스트처럼 격리 실행을 위해
#      복사된 파일은 실제 저장소 코퍼스가 아니므로 추적 대상으로 한정해 오탐을 막는다.
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

main() {
  check_reference_links
  check_orphaned_files
  check_code_fences
  check_index_freshness
  check_readme_skill_counts
  check_archive_scope_consistency
  check_dangling_file_references
  if [ -f "$CONTEXTS_DIR/prompt-architect/evals/routing/run.sh" ]; then
    bash "$CONTEXTS_DIR/prompt-architect/evals/routing/run.sh" --check-cases-only || EXIT_CODE=1
  fi

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
