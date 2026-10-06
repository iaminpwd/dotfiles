#!/usr/bin/env bash
# prompt-lint.sh 회귀 테스트
#
# 현재 prompt corpus의 구조적 계약만 검증한다:
# - reference 링크 / orphan reference
# - 코드펜스
# - INDEX / README drift
# - 숨김 contexts 디렉토리 제외
# - dangling 저장소 경로
# - routing 정답지 정합성

set -euo pipefail
export QUIET=0

REPO_ROOT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LINT="bin/linters/prompt-lint.sh"

PASS_COUNT=0
FAIL_COUNT=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TODAY=$(date +%F)

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

build_base() {
  local base=$1
  mkdir -p "$base/contexts/demo/references"
  cat >"$base/contexts/demo/SKILL.md" <<EOF
---
name: demo
description: 픽스처용 데모 스킬
reviewed: $TODAY
---
# 데모 스킬

## 작업 유형별 참조 문서 라우팅

| 작업 유형 | 참조 문서 |
|---|---|
| 공통 원칙 | references/000-core.md |
| 데모 코어 | references/010-demo-core.md |
EOF

  cat >"$base/contexts/demo/references/000-core.md" <<EOF
---
role: Demo Core
reviewed: $TODAY
---
# 000. 데모 코어

저장소 고유 공통 계약입니다.
EOF

  cat >"$base/contexts/demo/references/010-demo-core.md" <<EOF
---
role: Demo Module
reviewed: $TODAY
---
# 010. 데모 모듈

결정론적 출력을 사용합니다.
EOF
}

BASE="$TMP/_base"
build_base "$BASE"

new_case() {
  local dir="$TMP/$1"
  cp -a "$BASE" "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.name Test
  git -C "$dir" config user.email test@example.com
  mkdir -p "$dir/bin/linters" "$dir/bin/lib"
  cp "$REPO_ROOT_SRC/bin/linters/prompt-lint.sh" "$dir/bin/linters/prompt-lint.sh"
  cp "$REPO_ROOT_SRC/bin/lib/script-init.sh" "$dir/bin/lib/script-init.sh"
  echo "$dir"
}

check() {
  local name=$1 want_code=$2 want_text=$3 dir=$4
  local out code
  out=$( (cd "$dir" && bash "$LINT") 2>&1) && code=0 || code=$?
  if [ "$code" -ne "$want_code" ]; then
    report "$name" 1 "기대 exit=$want_code / 실제 exit=$code — $(echo "$out" | tail -1)"
    return
  fi
  if ! grep -qF "$want_text" <<<"$out"; then
    report "$name" 1 "출력에 '$want_text' 가 없습니다 — $(grep -E 'ERROR|WARNING' <<<"$out" | head -1)"
    return
  fi
  report "$name" 0
}

check_clean() {
  local name=$1 dir=$2
  local out code hits
  out=$( (cd "$dir" && bash "$LINT") 2>&1) && code=0 || code=$?
  if [ "$code" -ne 0 ]; then
    report "$name" 1 "기대 exit=0 / 실제 exit=$code — $(echo "$out" | tail -1)"
    return
  fi
  hits=$(grep -cE '\[(ERROR|WARNING)\]' <<<"$out" || true)
  if [ "$hits" -ne 0 ]; then
    report "$name" 1 "지적 ${hits}건: $(grep -E '\[(ERROR|WARNING)\]' <<<"$out" | head -2 | tr '\n' ' ')"
    return
  fi
  report "$name" 0
}

echo "=== prompt-lint.sh 회귀 테스트 ==="
echo "--- 기준선 ---"
check_clean "ok-baseline" "$(new_case ok-baseline)"

echo "--- reference 링크 / orphan ---"
D=$(new_case fail-broken-relative-reference)
echo '| 없는 모듈 | references/999-missing.md |' >>"$D/contexts/demo/SKILL.md"
check "fail-broken-relative-reference" 1 "깨진 스킬-상대 참조 링크" "$D"

D=$(new_case fail-broken-absolute-reference)
echo '상세 계약: contexts/demo/references/999-missing.md' >>"$D/contexts/demo/SKILL.md"
check "fail-broken-absolute-reference" 1 "깨진 참조 링크" "$D"

D=$(new_case warn-orphaned-reference)
cat >"$D/contexts/demo/references/020-orphan.md" <<EOF
---
role: Orphan
reviewed: $TODAY
---
# 020. 고아
EOF
check "warn-orphaned-reference" 0 "고아 후보" "$D"

echo "--- markdown 구조 ---"
D=$(new_case fail-odd-code-fence)
printf '\n\`\`\`bash\necho hello\n' >>"$D/contexts/demo/references/010-demo-core.md"
check "fail-odd-code-fence" 1 "코드펜스 짝이 맞지 않음" "$D"

echo "--- contexts 숨김 디렉토리 제외 ---"
D=$(new_case fail-contexts-find-no-prune)
mkdir -p "$D/bin/utils"
cat >"$D/bin/utils/scan-rules.sh" <<'EOF'
#!/usr/bin/env bash
CONTEXTS_DIR="$REPO_ROOT/contexts"
find "$CONTEXTS_DIR" -name '*.md'
EOF
git -C "$D" add bin/utils/scan-rules.sh
check "fail-contexts-find-no-prune" 1 "숨김 디렉토리 제외가 없습니다" "$D"

D=$(new_case ok-contexts-find-scoped)
mkdir -p "$D/bin/utils"
cat >"$D/bin/utils/scan-one-skill.sh" <<'EOF'
#!/usr/bin/env bash
CONTEXTS_DIR="$REPO_ROOT/contexts"
find "$CONTEXTS_DIR/$1/references" -maxdepth 1 -name '*.md'
EOF
git -C "$D" add bin/utils/scan-one-skill.sh
check_clean "ok-contexts-find-scoped" "$D"

D=$(new_case fail-ansible-find-no-guard)
mkdir -p "$D/ansible/roles/demo/tasks"
cat >"$D/ansible/roles/demo/tasks/main.yml" <<'EOF'
---
- name: 스크립트 검색
  ansible.builtin.find:
    paths: "{{ role_path }}/../../../contexts"
    file_type: file
    patterns: "*.sh"
    recurse: true
  register: demo_scripts

- name: 링크
  ansible.builtin.file:
    src: "{{ item.path }}"
    dest: "{{ ansible_env.HOME }}/.local/bin/{{ item.path | basename }}"
    state: link
  loop: "{{ demo_scripts.files }}"
EOF
git -C "$D" add ansible/roles/demo/tasks/main.yml
check "fail-ansible-find-no-guard" 1 "경로 가드가 없습니다" "$D"

D=$(new_case fail-ansible-guard-in-comment-only)
mkdir -p "$D/ansible/roles/demo/tasks"
cat >"$D/ansible/roles/demo/tasks/main.yml" <<'EOF'
---
# '/contexts/.' not in item.path 로 제외해야 한다.
- name: 스크립트 검색
  ansible.builtin.find:
    paths: "{{ role_path }}/../../../contexts"
    file_type: file
    recurse: true
  register: demo_scripts
EOF
git -C "$D" add ansible/roles/demo/tasks/main.yml
check "fail-ansible-guard-in-comment-only" 1 "경로 가드가 없습니다" "$D"

D=$(new_case ok-ansible-find-guarded)
mkdir -p "$D/ansible/roles/demo/tasks"
cat >"$D/ansible/roles/demo/tasks/main.yml" <<'EOF'
---
- name: 스크립트 검색
  ansible.builtin.find:
    paths: "{{ role_path }}/../../../contexts"
    file_type: file
    recurse: true
  register: demo_scripts

- name: 링크
  ansible.builtin.file:
    src: "{{ item.path }}"
    dest: "{{ ansible_env.HOME }}/.local/bin/{{ item.path | basename }}"
    state: link
  loop: "{{ demo_scripts.files }}"
  when: "'/contexts/.' not in item.path"
EOF
git -C "$D" add ansible/roles/demo/tasks/main.yml
check_clean "ok-ansible-find-guarded" "$D"

echo "--- INDEX freshness ---"
GENERATOR_SRC="$REPO_ROOT_SRC/bin/utils/generate-context-index.sh"

D=$(new_case warn-stale-index)
mkdir -p "$D/bin/utils"
cp "$GENERATOR_SRC" "$D/bin/utils/generate-context-index.sh"
echo "# 낡은 색인" >"$D/contexts/INDEX.md"
check "warn-stale-index" 0 "어긋납니다" "$D"

D=$(new_case ok-fresh-index)
mkdir -p "$D/bin/utils"
cp "$GENERATOR_SRC" "$D/bin/utils/generate-context-index.sh"
(cd "$D" && bash bin/utils/generate-context-index.sh) >"$D/contexts/INDEX.md"
check_clean "ok-fresh-index" "$D"
if grep -qF '## demo' "$D/contexts/INDEX.md" && [ -s "$D/contexts/INDEX.md" ]; then
  report "generate-context-index emits skill" 0
else
  report "generate-context-index emits skill" 1 "생성된 INDEX.md에 demo가 없습니다"
fi

D=$(new_case ok-singleline-desc-index)
mkdir -p "$D/bin/utils"
cp "$GENERATOR_SRC" "$D/bin/utils/generate-context-index.sh"
cat >"$D/contexts/demo/SKILL.md" <<'EOF'
---
name: demo
description: "단일행 설명입니다."
---
# demo Skill
EOF
(cd "$D" && bash bin/utils/generate-context-index.sh) >"$D/contexts/INDEX.md"
if grep -qF '단일행 설명입니다.' "$D/contexts/INDEX.md" && ! grep -qF -- '---' "$D/contexts/INDEX.md"; then
  report "generate-context-index single-line description" 0
else
  report "generate-context-index single-line description" 1
fi

echo "--- README reference count ---"
D=$(new_case readme-count-match)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 구성 | 주요 커버리지 |
|---|---|---|
| **Demo** (`demo/`) | 2개 reference | 데모 |
EOF
check_clean "readme-count-match" "$D"

D=$(new_case readme-count-drift)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 구성 | 주요 커버리지 |
|---|---|---|
| **Demo** (`demo/`) | 9개 reference | 데모 |
EOF
check "readme-count-drift" 0 "모듈 수가 실제와 다릅니다" "$D"

D=$(new_case readme-missing-reference-dir)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 구성 | 주요 커버리지 |
|---|---|---|
| **Gone** (`gone/`) | 3개 reference | 제거된 스킬 |
EOF
check "readme-missing-reference-dir" 0 "references 디렉토리가 없습니다" "$D"

D=$(new_case readme-skill-only)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 구성 | 주요 커버리지 |
|---|---|---|
| **Demo** (`demo/`) | `SKILL.md` 단일 문서 | 데모 |
EOF
check_clean "readme-skill-only" "$D"

echo "--- dangling repository paths ---"
D=$(new_case fail-dangling-file-reference)
mkdir -p "$D/bin/linters"
echo '# contexts/demo/references/gone.md 에서 이미 고쳤다.' >"$D/bin/linters/note.sh"
git -C "$D" add bin/linters/note.sh
check "fail-dangling-file-reference" 1 "존재하지 않는 파일을 가리키는 참조" "$D"

D=$(new_case ok-dangling-ref-inside-tests)
mkdir -p "$D/contexts/demo/tests"
echo '# contexts/demo/references/synthetic.md 픽스처를 만든다.' >"$D/contexts/demo/tests/run.sh"
git -C "$D" add contexts/demo/tests/run.sh
check_clean "ok-dangling-ref-inside-tests" "$D"

D=$(new_case ok-placeholder-path)
mkdir -p "$D/bin/linters"
echo '# 예시: contexts/example-skill/custom-role.md 처럼 배치하십시오.' >"$D/bin/linters/note.sh"
git -C "$D" add bin/linters/note.sh
check_clean "ok-placeholder-path" "$D"

echo "--- routing answer key ---"
D=$(new_case fail-routing-unknown-skill)
mkdir -p "$D/contexts/prompt-architect/evals/routing"
cp "$REPO_ROOT_SRC/contexts/prompt-architect/evals/routing/run.sh" "$D/contexts/prompt-architect/evals/routing/run.sh"
printf 'S01\tremoved-skill\t입력\n' >"$D/contexts/prompt-architect/evals/routing/cases.tsv"
check "routing unknown skill" 1 "라우팅 정답에 없는 스킬" "$D"

printf 'S01\tdemo\t입력\n' >"$D/contexts/prompt-architect/evals/routing/cases.tsv"
check "routing valid skill" 0 "라우팅 케이스 정합성 확인" "$D"

printf 'S01\tdemo\t입력\nS01\tnone\t입력\n' >"$D/contexts/prompt-architect/evals/routing/cases.tsv"
check "routing duplicate id" 1 "라우팅 케이스 ID 중복" "$D"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
