#!/usr/bin/env bash
# prompt-lint.sh 회귀 테스트
#
# prompt-lint.sh 는 프롬프트 코퍼스의 결함을 잡는 11개 검사를 담고 있는데, 정작
# 자기 자신은 검증되지 않아 두 번이나 조용히 죽었다(2026-07-27: grep 무매치가
# set -euo pipefail 에 걸려 아무 메시지 없이 exit 1). 린터가 죽으면 코퍼스가
# 깨끗해서 통과한 것인지 검사가 실행조차 안 된 것인지 구분할 수 없다.
#
# 각 케이스는 최소 코퍼스를 임시 디렉토리에 조립하고 실제 prompt-lint.sh 를
# 그 위에서 실행한다. 검사 대상 경로가 REPO_ROOT 기준이므로 케이스마다 git init
# 을 해 린터가 케이스 디렉토리를 저장소 루트로 인식하게 만든다.
#
# 사용: bash ~/dotfiles/contexts/prompt-architect/tests/test_prompt_lint.sh

set -euo pipefail
export QUIET=0

LINT="prompt-lint.sh"

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
# 최소 코퍼스: 11개 검사를 모두 통과하는 상태. 각 케이스는 여기서 한 군데만 어긋뜨린다.
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

# 2b. 깨진 참조 링크(스킬 루트 role.*.md / scripts 하위 디렉토리). 두 배치는 예전
#     정규식이 매칭하지 못해 경로가 깨져도 조용히 통과했다(2026-07-28 실측).
D=$(new_case fail-broken-link-nested)
{
  echo "| 역할 지침 | contexts/demo/role.missing.md |"
  echo "| 위임 검증기 | contexts/demo/scripts/preflight/demo-check.sh |"
} >>"$D/contexts/demo/SKILL.md"
check "fail-broken-link-nested (role.*.md / scripts 하위)" 1 "깨진 참조 링크" "$D"

# 2c. 룰북에서 삭제된 조항을 contexts/README.md 가 계속 인용. 커밋 393926b 가
#     base.AGENTS.md 9장의 자가 진화 조항 2개를 지웠는데도 인용 4곳이 전부 통과했던
#     실측 사건(2026-07-28)을 고정한다.
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
#     구현이 `printf | grep -q` 였을 때 SIGPIPE + pipefail 로 실재 조항 20건이 전부
#     오탐으로 뒤집혔다(2026-07-28 실측).
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

# 4. 벤더 용어 오염: azure 폴더 밖에 azurecr.io 를 둔다.
D=$(new_case fail-azurecr-outside-azure)
echo "- 예시 레지스트리: myregistry.azurecr.io" >>"$D/contexts/demo/references/010-demo-core.md"
check "fail-azurecr-outside-azure" 1 "azurecr.io 발견" "$D"

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

# 10. aws/azure 미러링 조항 수 불일치.
D=$(new_case warn-mirror-asymmetry)
mkdir -p "$D/contexts/aws/references" "$D/contexts/azure/references"
cat >"$D/contexts/aws/references/010-aws-core.md" <<EOF
---
role: AWS Core
reviewed: $TODAY
---
# 9. AWS 코어

- **[MUST] Tagging:** 모든 리소스에 태그를 부여하십시오.
- **[MUST] Encryption:** 저장 데이터를 암호화하십시오.
EOF
cat >"$D/contexts/azure/references/010-azure-core.md" <<EOF
---
role: Azure Core
reviewed: $TODAY
---
# 9. Azure 코어

- **[MUST] Tagging:** 모든 리소스에 태그를 부여하십시오.
EOF
check "warn-mirror-asymmetry" 0 "조항 수 불일치" "$D"

echo "--- 린터 자신의 조용한 사망 회귀 (2026-07-27 실측 버그) ---"

# 11. 개념이 aws/azure 에만 있으면 grep -vc 가 0을 세고 종료 코드 1을 반환한다.
#     예전에는 그 1이 set -e 에 걸려 린터가 아무 메시지 없이 죽었다.
D=$(new_case ok-concept-only-in-aws-azure)
mkdir -p "$D/contexts/aws/references" "$D/contexts/azure/references"
for v in aws azure; do
  cat >"$D/contexts/$v/references/010-$v-core.md" <<EOF
---
role: ${v} Core
reviewed: $TODAY
---
# 9. ${v} 코어

- **[MUST] Observability:** SLI/SLO 를 정의하십시오.
EOF
done
check_clean "ok-concept-only-in-aws-azure (완주)" "$D"

# 12. 숫자 접두사 없는 aws 참조 파일이 있으면 grep -oE '^[0-9]{3}' 가 무매치로 1을
#     반환한다. 예전에는 여기서도 린터가 메시지 없이 죽었다.
D=$(new_case ok-aws-ref-without-numeric-prefix)
mkdir -p "$D/contexts/aws/references"
cat >"$D/contexts/aws/references/notes.md" <<EOF
---
role: AWS Notes
reviewed: $TODAY
---
# 메모

- 숫자 접두사가 없는 참조 파일.
EOF
check "ok-aws-ref-without-numeric-prefix (완주)" 0 "Prompt Corpus Lint Passed" "$D"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
