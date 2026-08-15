#!/usr/bin/env bash
# prompt-lint.sh 회귀 테스트
#
# prompt-lint.sh 는 프롬프트 코퍼스의 결함을 잡는 여러 검사를 담고 있는데, 정작
# 자기 자신은 검증되지 않으면 grep 무매치 하나가 set -euo pipefail 에 걸려 아무
# 메시지 없이 exit 1로 죽어도 알 수 없다. 린터가 죽으면 코퍼스가 깨끗해서 통과한
# 것인지 검사가 실행조차 안 된 것인지 구분할 수 없다.
#
# 각 케이스는 최소 코퍼스를 임시 디렉토리에 조립하고 실제 prompt-lint.sh 를
# 그 위에서 실행한다. prompt-lint.sh는 자기 자신의 물리적 위치(bin/linters/)를
# 기준으로 REPO_ROOT를 고정하므로(CWD 비의존), 격리 픽스처로 테스트하려면 실제
# 스크립트와 그 의존 라이브러리를 케이스 디렉토리의 동일한 상대 위치(bin/linters/,
# bin/lib/)로 함께 복사해야 한다(test-pre-push-hook.sh가 run-suite.sh를 다루는
# 방식과 동일한 이유).
#
# 사용: bash ~/dotfiles/contexts/prompt-architect/tests/test_prompt_lint.sh

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

# -----------------------------------------------------------------------------
# 최소 코퍼스: 전 검사를 통과하는 상태. 각 케이스는 여기서 한 군데만 어긋뜨린다.
# (개수를 적으면 검사가 늘 때마다 조용히 낡으므로 여기서는 수를 명시하지 않는다.)
# -----------------------------------------------------------------------------
BASE="$TMP/_base"
build_base() {
  mkdir -p "$BASE/contexts/demo/references"

  cat >"$BASE/contexts/demo/SKILL.md" <<EOF
---
name: demo
description: 픽스처용 데모 스킬
reviewed: $TODAY
---
# 데모 스킬

| 작업 유형 | 참조 문서 |
|---|---|
| 공통 원칙 | contexts/demo/references/000-core.md |
| 데모 코어 | contexts/demo/references/010-demo-core.md |
EOF

  cat >"$BASE/contexts/demo/references/000-core.md" <<EOF
---
role: Demo Core
reviewed: $TODAY
---
# 000. 데모 코어

- **[MUST] 공통 자가 비판 절차 (전 demo 모듈 SSOT):** 하위 참조 모듈(010)에 나열된 점검 기준을 하나씩 대조하십시오.
EOF

  cat >"$BASE/contexts/demo/references/010-demo-core.md" <<EOF
---
role: Demo Module
reviewed: $TODAY
---
# 9. 데모 모듈

- **[MUST] Deterministic Output:** 출력은 결정론적이어야 합니다.
EOF
}

# 케이스 디렉토리를 만들고 경로를 돌려준다.
new_case() {
  local dir="$TMP/$1"
  cp -a "$BASE" "$dir"
  git -C "$dir" init -q
  # prompt-lint.sh(및 그 의존 라이브러리 script-init.sh)를 실제 저장소와 동일한
  # 상대 위치로 복사한다. 자기 자신의 물리적 위치를 기준으로 REPO_ROOT를 고정하는
  # 스크립트라, PATH의 정본을 그냥 호출하면 이 케이스 디렉토리가 아니라 실제
  # dotfiles 저장소를 대상으로 린트해버린다.
  mkdir -p "$dir/bin/linters" "$dir/bin/lib"
  cp "$REPO_ROOT_SRC/bin/linters/prompt-lint.sh" "$dir/bin/linters/prompt-lint.sh"
  cp "$REPO_ROOT_SRC/bin/lib/script-init.sh" "$dir/bin/lib/script-init.sh"
  echo "$dir"
}

# check <케이스명> <기대 종료코드> <출력에 포함되어야 할 문구>
check() {
  local name=$1 want_code=$2 want_text=$3 dir="$4"
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

# 경고/에러가 하나도 없어야 하는 케이스용.
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

build_base

echo "=== prompt-lint.sh 회귀 테스트 ==="

echo "--- 기준선 ---"
check_clean "ok-baseline (지적 0건)" "$(new_case ok-baseline)"

echo "--- ERROR (커밋 중단) ---"

# 1. SSOT 모듈 목록 불일치: 선언에 없는 모듈 파일을 추가한다.
D=$(new_case fail-ssot-mismatch)
cat >"$D/contexts/demo/references/020-extra.md" <<EOF
---
role: Extra Module
reviewed: $TODAY
---
# 19. 추가 모듈
EOF
echo "| 추가 모듈 | contexts/demo/references/020-extra.md |" >>"$D/contexts/demo/SKILL.md"
check "fail-ssot-mismatch" 1 "SSOT 모듈 목록 불일치" "$D"

# 2. 깨진 참조 링크: 존재하지 않는 모듈을 라우팅 테이블에 적는다.
D=$(new_case fail-broken-link)
echo "| 없는 모듈 | contexts/demo/references/999-missing.md |" >>"$D/contexts/demo/SKILL.md"
check "fail-broken-link" 1 "깨진 참조 링크" "$D"

# 2b. 깨진 참조 링크(스킬 루트 role.*.md / scripts 하위 디렉토리). 두 패턴 모두
#     정규식이 매칭하지 못하면 경로가 깨져도 조용히 통과할 수 있어 회귀로 고정한다.
D=$(new_case fail-broken-link-nested)
{
  echo "| 역할 지침 | contexts/demo/role.missing.md |"
  echo "| 위임 검증기 | bin/hooks/plugins/demo-check.sh |"
} >>"$D/contexts/demo/SKILL.md"
check "fail-broken-link-nested (role.*.md / scripts 하위)" 1 "깨진 참조 링크" "$D"

# 2c. 룰북에서 삭제된 조항을 contexts/README.md 가 계속 인용하면 잡아내야 한다
#     (조항이 삭제돼도 문서의 인용이 낡은 채로 남는 회귀).
D=$(new_case fail-documented-clause-missing)
cat >"$D/contexts/README.md" <<'EOF'
# 프롬프트 아키텍처 문서

**적용 사례:**
```markdown
- **[Trigger: After Code Change] Ghost Clause Never Defined:** 이 조항은 어떤 룰북에도 없습니다.
```
EOF
check "fail-documented-clause-missing" 1 "룰북에 없는 조항을 문서가 인용" "$D"

# 2d. 위 검사의 오탐 회귀: 실재하는 조항을 인용한 README 는 통과해야 한다.
#     `printf | grep -q` 형태로 구현하면 SIGPIPE + pipefail 로 실재하는 조항까지
#     전부 오탐으로 뒤집힐 수 있다.
D=$(new_case ok-documented-clause-present)
cat >"$D/contexts/README.md" <<'EOF'
# 프롬프트 아키텍처 문서

**적용 사례:**
```markdown
- **[MUST] Deterministic Output:** 출력은 결정론적이어야 합니다.
```
EOF
check_clean "ok-documented-clause-present (오탐 없음)" "$D"

# 3. 코드펜스 짝 불일치: 여는 펜스만 남긴다.
D=$(new_case fail-odd-code-fence)
printf '\n```bash\necho hello\n' >>"$D/contexts/demo/references/010-demo-core.md"
check "fail-odd-code-fence" 1 "코드펜스 짝이 맞지 않음" "$D"

# 4. 벤더 용어 오염: 룰북에 벤더 종속 레지스트리(azurecr.io)를 하드코딩한다.
D=$(new_case fail-azurecr-in-rulebook)
echo "- 예시 레지스트리: myregistry.azurecr.io" >>"$D/contexts/demo/references/010-demo-core.md"
check "fail-azurecr-in-rulebook" 1 "azurecr.io 발견" "$D"

# 5. 벤더 용어 오염: aws 폴더에 Azure 전용 병기(IAM/RBAC)를 둔다.
D=$(new_case fail-iam-rbac-in-aws)
mkdir -p "$D/contexts/aws/references"
cat >"$D/contexts/aws/references/010-aws-core.md" <<EOF
---
role: AWS Core
reviewed: $TODAY
---
# 9. AWS 코어

- **[MUST] Least Privilege:** IAM/RBAC 권한을 최소화하십시오.
EOF
check "fail-iam-rbac-in-aws" 1 "'IAM/RBAC' 병기 발견" "$D"

# 5b~5d. 예외 마커 무결성(check_exception_hook_integrity).
#
# base.AGENTS.md 의 [CORE EXCEPTION HOOK] 은 스킬이 전역 룰을 완화하려면 완화 대상을
# 개별 열거하도록 요구하고, 그 형식 준수를 prompt-lint.sh 가 자동 검증한다고 선언한다.
# 그런데 이 검사에는 회귀 케이스가 하나도 없었다 — 함수 본문을 통째로 `return 0` 으로
# 바꿔도 스위트가 25/25 로 통과했다(뮤테이션 실측). 즉 게이트가 죽어도 아무도 모르는
# 상태에서, 이 저장소의 contexts/dotfiles/SKILL.md 를 포함한 실제 예외 선언들이
# 무검증으로 통과할 수 있었다. 통과·차단 양쪽 축을 함께 고정한다.
#
# 이 검사는 contexts/base.AGENTS.md 가 있어야 발동하므로(없으면 조용히 건너뜀),
# 기준선 코퍼스가 아니라 각 케이스에서만 심는다.
write_base_agents() {
  cat >"$1/contexts/base.AGENTS.md" <<'EOF'
# 공통 메타 프롬프트 엔진

- **[MUST] Deterministic Output:** 출력은 결정론적이어야 합니다.
- **[PREFER] Caution Over Speed:** 속도보다 정확성을 우선합니다.
EOF
}

# 5b. 정상 선언: 실재하는 룰 이름을 개별 열거하면 통과해야 한다(오탐 회귀).
D=$(new_case ok-exception-marker)
write_base_agents "$D"
cat >>"$D/contexts/demo/SKILL.md" <<'EOF'

> **[ EXCEPTION APPLIED: Caution Over Speed ]**
> - **Caution Over Speed** (`base.AGENTS.md` 최상단): 자동화된 안전망이 대체하므로 생략.
EOF
check "ok-exception-marker (실재 룰 개별 열거는 통과)" 0 "예외 마커 무결성 검사 완료" "$D"

# 5c. 범위를 특정하지 않은 블랑켓 선언은 차단해야 한다.
D=$(new_case fail-exception-blanket)
write_base_agents "$D"
cat >>"$D/contexts/demo/SKILL.md" <<'EOF'

> **[ EXCEPTION APPLIED: 전체 무효화 ]**
> - **Deterministic Output** (`base.AGENTS.md`): 근거.
EOF
check "fail-exception-blanket (범위 미특정 무효화 차단)" 1 "범위를 특정하지 않은 예외 선언" "$D"

# 5d. 열거된 이름이 base.AGENTS.md 에 실재하지 않으면(개명·삭제·오타) 차단해야 한다.
#     이게 이 검사의 본래 목적이다 — 룰 이름이 바뀌면 예외 선언이 조용히 낡아,
#     아무 룰도 완화하지 않으면서 완화한 것처럼 보이는 상태가 된다.
D=$(new_case fail-exception-ghost-rule)
write_base_agents "$D"
cat >>"$D/contexts/demo/SKILL.md" <<'EOF'

> **[ EXCEPTION APPLIED: Exhaustive Review ]**
> - **Exhaustive Review** (`base.AGENTS.md` §5.2): 이 룰은 base.AGENTS.md 에 실재하지 않는다.
EOF
check "fail-exception-ghost-rule (실재하지 않는 룰 열거 차단)" 1 "base.AGENTS.md에 실재하지 않음" "$D"

# 5e~5h. contexts/ 스캔의 숨김 디렉토리 제외 일관성(check_archive_scope_consistency).
#
# .archive/.shared 를 "어떤 소비자도 취급하지 않는다"는 규약은 셸 glob 에서만 자동으로
# 지켜진다. find 와 ansible.builtin.find 는 숨김 디렉토리 안으로 그대로 들어가므로 손으로
# 제외해야 하는데, 실제로 두 곳을 빠뜨려 폐기 스킬의 스크립트가 사용자 PATH 에 링크되고
# 폐기 룰북이 근거 기록에 섞였다. 두 결함의 수정 직전 커밋 상태에서 이 검사가 실제로
# 검출됨을 확인하고 회귀로 고정한다.
#
# 오탐 축(5f/5h)을 함께 두는 이유: 판정을 넓히면 특정 스킬 하위만 지목하는 find 나
# 제외 조건을 이미 갖춘 ansible 태스크까지 걸려, 멀쩡한 코드가 커밋을 막는다.

# 5e. contexts 루트를 훑는 find 에 제외 토큰이 없으면 차단.
D=$(new_case fail-contexts-find-no-prune)
mkdir -p "$D/bin/utils"
cat >"$D/bin/utils/scan-rules.sh" <<'EOF'
#!/usr/bin/env bash
CONTEXTS_DIR="$REPO_ROOT/contexts"
matches=$(find "$CONTEXTS_DIR" -iname "$1" 2>/dev/null)
echo "$matches"
EOF
check "fail-contexts-find-no-prune (셸 find 제외 누락 차단)" 1 "숨김 디렉토리 제외가 없습니다" "$D"

# 5f. 특정 스킬 하위를 지목하는 find 는 구조적으로 .archive 에 닿을 수 없으므로 통과.
D=$(new_case ok-contexts-find-scoped)
mkdir -p "$D/bin/utils"
cat >"$D/bin/utils/scan-one-skill.sh" <<'EOF'
#!/usr/bin/env bash
CONTEXTS_DIR="$REPO_ROOT/contexts"
rhs_file=$(find "$CONTEXTS_DIR/$1/references" -maxdepth 1 -name "*.md" | head -1)
echo "$rhs_file"
EOF
check "ok-contexts-find-scoped (스킬 하위 지목은 오탐 없음)" 0 "제외 일관성 검사 완료" "$D"

# 5g. contexts 를 recurse 스캔하는 ansible find 가 경로 가드 토큰을 갖고 있지 않으면 차단.
#     제외 조건이 find 태스크가 아니라 결과를 loop 하는 별도 태스크의 when: 에 붙는
#     구조라, 태스크 블록이 아니라 파일 단위로 본다.
D=$(new_case fail-ansible-find-no-guard)
mkdir -p "$D/ansible/roles/demo/tasks"
cat >"$D/ansible/roles/demo/tasks/main.yml" <<'EOF'
---
- name: 스크립트 검색
  ansible.builtin.find:
    paths:
      - "{{ role_path }}/../../../contexts"
    file_type: file
    patterns: "*.sh"
    recurse: true
  register: demo_scripts

- name: 링크
  ansible.builtin.file:
    src: "{{ item.path }}"
    dest: "{{ ansible_env.HOME }}/.local/bin/{{ item.path | basename }}"
    state: link
    force: true
  loop: "{{ demo_scripts.files }}"
  when: "'/scripts/' in item.path"
EOF
check "fail-ansible-find-no-guard (ansible recurse 스캔 가드 누락 차단)" 1 "경로 가드가 없습니다" "$D"

# 5g-2. 가드 토큰이 "주석에만" 있으면 통과시키면 안 된다. 주석 언급을 근거로 인정하는
#       순간 게이트가 무력화된다 — test-coverage-check.sh 의 run.sh 등록 검사가 실측으로
#       겪은 것과 같은 구멍이다(설명 주석을 넣었더니 실제 등록을 빼도 통과). 위 5g 케이스는
#       주석이 아예 없어서 주석 제거 로직을 없애도 검출되지 않았다(뮤테이션 실측).
D=$(new_case fail-ansible-guard-in-comment-only)
mkdir -p "$D/ansible/roles/demo/tasks"
cat >"$D/ansible/roles/demo/tasks/main.yml" <<'EOF'
---
# 주의: 링크 대상에서 '/contexts/.' 하위(폐기 스킬)는 빼야 한다.
# (설명만 있고 아래 when: 에는 실제 조건이 없다 — 이 상태를 통과시키면 안 된다.)
- name: 스크립트 검색
  ansible.builtin.find:
    paths:
      - "{{ role_path }}/../../../contexts"
    file_type: file
    patterns: "*.sh"
    recurse: true
  register: demo_scripts

- name: 링크
  ansible.builtin.file:
    src: "{{ item.path }}"
    dest: "{{ ansible_env.HOME }}/.local/bin/{{ item.path | basename }}"
    state: link
    force: true
  loop: "{{ demo_scripts.files }}"
  when: "'/scripts/' in item.path"
EOF
check "fail-ansible-guard-in-comment-only (주석 언급은 근거로 인정 안 함)" 1 "경로 가드가 없습니다" "$D"

# 5h. 같은 태스크에 경로 가드가 있으면 통과해야 한다(오탐 회귀). 주석이 아니라 본문에
#     토큰이 있어야 인정되는지도 이 케이스가 함께 고정한다.
D=$(new_case ok-ansible-find-guarded)
mkdir -p "$D/ansible/roles/demo/tasks"
cat >"$D/ansible/roles/demo/tasks/main.yml" <<'EOF'
---
- name: 스크립트 검색
  ansible.builtin.find:
    paths:
      - "{{ role_path }}/../../../contexts"
    file_type: file
    patterns: "*.sh"
    recurse: true
  register: demo_scripts

- name: 링크
  ansible.builtin.file:
    src: "{{ item.path }}"
    dest: "{{ ansible_env.HOME }}/.local/bin/{{ item.path | basename }}"
    state: link
    force: true
  loop: "{{ demo_scripts.files }}"
  when: >
    '/scripts/' in item.path and
    '/contexts/.' not in item.path
EOF
check "ok-ansible-find-guarded (가드 있으면 오탐 없음)" 0 "제외 일관성 검사 완료" "$D"

echo "--- WARNING (통과시키되 보고) ---"

# 6. 고아 참조 파일: 라우팅 테이블(SKILL.md)에만 없는 모듈. SSOT 선언에는 넣어둬야
#    한다. 빼면 SSOT 목록 불일치 ERROR 가 먼저 걸려 고아 경고를 격리할 수 없다.
D=$(new_case warn-orphaned-reference)
cat >"$D/contexts/demo/references/020-orphan.md" <<EOF
---
role: Orphan Module
reviewed: $TODAY
---
# 19. 고아 모듈
EOF
sed -i 's/하위 참조 모듈(010)/하위 참조 모듈(010, 020)/' "$D/contexts/demo/references/000-core.md"
check "warn-orphaned-reference" 0 "고아 후보" "$D"

# 7. 파일 크기 제약(150줄) 초과.
D=$(new_case warn-file-size)
{
  for i in $(seq 1 160); do echo "- 라인 $i"; done
} >>"$D/contexts/demo/references/010-demo-core.md"
check "warn-file-size" 0 "150줄 제약 초과" "$D"

# 8. MUST 로 태깅됐지만 본문은 선호를 서술.
D=$(new_case warn-must-with-prefer-wording)
echo "- **[MUST] Prefer Small Modules:** 가급적 모듈을 작게 유지하십시오." >>"$D/contexts/demo/references/010-demo-core.md"
check "warn-must-with-prefer-wording" 0 "MUST 인데 본문이 선호를 서술함" "$D"

# 9. 고위험 키워드인데 Halt & Clarify 로 태깅(Hard Block 후보).
D=$(new_case warn-halt-on-high-risk)
echo "- 자격 증명 평문 노출이 감지되면 Halt & Clarify 하십시오." >>"$D/contexts/demo/references/010-demo-core.md"
check "warn-halt-on-high-risk" 0 "Hard Block 검토 필요" "$D"

# 10b. contexts/INDEX.md 최신성: 색인이 라우팅 테이블과 어긋나면 경고해야 한다.
#      실제 생성기(bin/utils/generate-context-index.sh)를 케이스 디렉토리에 그대로
#      복사해 넣는다 — check_index_freshness 는 PATH 가 아니라 REPO_ROOT 기준
#      상대 경로로 생성기를 찾으므로, 합성 코퍼스에도 물리적으로 있어야 한다.
GENERATOR_SRC="$REPO_ROOT_SRC/bin/utils/generate-context-index.sh"

D=$(new_case warn-stale-index)
mkdir -p "$D/bin/utils"
cp "$GENERATOR_SRC" "$D/bin/utils/generate-context-index.sh"
echo "# 낡은 색인" >"$D/contexts/INDEX.md"
check "warn-stale-index" 0 "어긋납니다" "$D"

# 10c. 위 검사의 오탐 회귀: 생성기로 방금 뽑아낸 색인은 경고 없이 통과해야 한다.
D=$(new_case ok-fresh-index)
mkdir -p "$D/bin/utils"
cp "$GENERATOR_SRC" "$D/bin/utils/generate-context-index.sh"
(cd "$D" && bash bin/utils/generate-context-index.sh) >"$D/contexts/INDEX.md"
check_clean "ok-fresh-index (오탐 없음)" "$D"

# 16. README 스킬 표의 모듈 수 대조. 이 저장소는 스킬을 .archive 로 옮기거나 룰북을
#     통폐합해도 문서의 개수만 그대로 남는 드리프트가 실제로 있었다(활성 스킬이 9개가
#     된 뒤에도 문서·주석 5곳이 "12개"를, 표가 Dotfiles "10개(000~060)"를 주장 — 실제는
#     6개(010~060)). 산문 쪽 숫자는 개수 비의존 표현으로 걷어냈지만 표는 숫자가 형식상
#     불가피하므로 그 축만 기계적으로 고정한다. 셋을 함께 본다: 일치하면 무경고,
#     어긋나면 경고, 표에만 남은(아카이브된) 스킬도 경고.
#     base 코퍼스에는 README 가 없어 나머지 케이스는 "README 없음 -> 건너뜀" 경로를 탄다.
D=$(new_case readme-count-match)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 모듈 수 | 주요 커버리지 |
|---|---|---|
| **Demo** (`demo/`) | 2개 (`000`~`010`) | 픽스처용 데모 |
EOF
check_clean "readme-count-match (표가 실제와 일치하면 무경고)" "$D"

D=$(new_case readme-count-drift)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 모듈 수 | 주요 커버리지 |
|---|---|---|
| **Demo** (`demo/`) | 9개 (`000`~`010`) | 픽스처용 데모 |
EOF
check "readme-count-drift (개수 불일치 경고)" 0 "README 스킬 표의 모듈 수가 실제와 다릅니다" "$D"

D=$(new_case readme-archived-skill)
cat >"$D/README.md" <<'EOF'
| 워크스페이스 | 모듈 수 | 주요 커버리지 |
|---|---|---|
| **Gone** (`gone/`) | 3개 (`010`~`030`) | 아카이브된 스킬 |
EOF
check "readme-archived-skill (표에만 남은 스킬 경고)" 0 "references 디렉토리가 없습니다" "$D"

# 17. 끊긴 파일 참조. 주석이 지목한 파일이 사라져도 아무것도 깨지지 않아 조용히 남는다.
#     실제로 tf-fixture-lib.sh 를 인라인한 뒤 그 파일을 가리키던 참조가 6곳 남았고,
#     손으로 훑어 고친 뒤에도 ansible 롤에 1곳이 더 있었다(이 검사가 그것을 잡아냈다).
#
#     이 검사는 `git ls-files` 로 "추적 중인 파일"만 본다. 그래서 케이스마다 대상 파일을
#     실제로 git add 해야 발동한다 — new_case 가 복사해 넣는 prompt-lint.sh 사본이
#     코퍼스로 오인되지 않게 하는 장치이므로, 이 전제를 바꾸면 오탐이 되돌아온다.
D=$(new_case fail-dangling-file-reference)
mkdir -p "$D/bin/linters"
echo "# 같은 함정을 contexts/demo/references/gone.md 에서 이미 고쳤다." >"$D/bin/linters/note.sh"
git -C "$D" add bin/linters/note.sh
check "fail-dangling-file-reference" 1 "존재하지 않는 파일을 가리키는 참조" "$D"

# 17b. 오탐 회귀 (a): tests/ 하위는 합성 트리를 만드는 것이 본업이라 없는 경로를
#      정당하게 쓴다. 실측에서 오탐 12건 중 11건이 여기였다.
D=$(new_case ok-dangling-ref-inside-tests)
mkdir -p "$D/contexts/demo/tests"
echo "# 픽스처로 contexts/demo/references/synthetic.md 를 만든다" >"$D/contexts/demo/tests/run.sh"
git -C "$D" add contexts/demo/tests/run.sh
check_clean "ok-dangling-ref-inside-tests (합성 픽스처는 오탐 아님)" "$D"

# 17c. 오탐 회귀 (b): 디렉토리부터 없으면 문서 템플릿의 자리표시자로 보고 넘긴다
#      (contexts/example-skill/custom-role.md 가 실제 그런 사례다).
D=$(new_case ok-placeholder-path)
mkdir -p "$D/bin/linters"
echo "# 예시: contexts/example-skill/custom-role.md 처럼 배치하십시오." >"$D/bin/linters/note.sh"
git -C "$D" add bin/linters/note.sh
check_clean "ok-placeholder-path (없는 디렉토리는 자리표시자)" "$D"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
