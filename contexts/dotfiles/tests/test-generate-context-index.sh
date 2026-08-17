#!/usr/bin/env bash
# test-generate-context-index.sh
#
# bin/utils/generate-context-index.sh 는 각 SKILL.md 의 라우팅 테이블을 그대로 이어붙여
# contexts/INDEX.md 를 만든다. 그런데 이 생성기에는 실제로 실행해 출력을 대조하는 테스트가
# 없었다 — 커버리지 게이트는 "이름이 tests/ 어딘가에 언급됐는가"만 보는데 그 조건이
# test-script-init.sh 의 설명 주석으로 이미 충족돼 있어서, 정작 판정 로직은 무방비였다.
# 실측(뮤테이션): 라우팅 테이블 추출 분기를 `if false` 로 죽여도 모든 스위트가 통과했고,
# 유일한 신호는 prompt-lint 의 [WARNING] 한 줄(rc=0, 비차단)이었다.
#
# 생성기는 CWD 와 무관하게 "자기 자신의 물리적 위치 기준"으로 저장소 루트를 잡는다
# (bin/utils/ 의 두 단계 위). 그래서 격리 검증을 하려면 실제 저장소가 아니라 합성 트리에
# 스크립트 사본을 배치해야 한다 — test_prompt_lint.sh 가 prompt-lint.sh 를 다루는 방식과
# 동일한 관용구다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-generate-context-index.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
GEN="$REPO_ROOT/bin/utils/generate-context-index.sh"

PASS_COUNT=0
FAIL_COUNT=0

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

echo "--- generate-context-index.sh (색인 생성기) ---"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 합성 저장소: <FAKE>/bin/utils/<생성기 사본> + <FAKE>/contexts/<스킬>/SKILL.md
FAKE="$TMP/fake-repo"
mkdir -p "$FAKE/bin/utils" "$FAKE/contexts/demo" "$FAKE/contexts/plain"
cp "$GEN" "$FAKE/bin/utils/generate-context-index.sh"

# 라우팅 테이블이 있는 스킬
cat >"$FAKE/contexts/demo/SKILL.md" <<'EOF'
---
name: demo
description: 데모 스킬 설명 한 줄
---

# Demo Skill

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 첫 번째 작업 | references/010-demo-core.md |
| 두 번째 작업 | references/020-demo-extra.md |

## 2. 그 밖의 절

이 문단은 표가 끝난 뒤라 색인에 들어가면 안 된다.
EOF

# 라우팅 테이블이 없는 단일 문서 스킬
cat >"$FAKE/contexts/plain/SKILL.md" <<'EOF'
---
name: plain
description: 표가 없는 단일 문서 스킬
---

# Plain Skill

라우팅 테이블이 없다.
EOF

OUT_FILE="$TMP/out.md"
code=0
bash "$FAKE/bin/utils/generate-context-index.sh" >"$OUT_FILE" 2>"$TMP/err" || code=$?
OUT=$(cat "$OUT_FILE")

if [ "$code" -eq 0 ]; then
  report "생성기 정상 종료" 0
else
  report "생성기 정상 종료" 1 "exit=$code err=$(cat "$TMP/err")"
fi

# 1. 라우팅 테이블 행이 그대로 실려야 한다. 이 스위트의 핵심 — 추출 분기가 죽으면 여기서 걸린다.
if grep -qF "references/010-demo-core.md" <<<"$OUT" &&
  grep -qF "references/020-demo-extra.md" <<<"$OUT"; then
  report "라우팅 테이블 행이 색인에 포함됨" 0
else
  report "라우팅 테이블 행이 색인에 포함됨" 1 "out=$OUT"
fi

# 2. 표가 끝난 뒤의 본문은 들어오면 안 된다(awk 가 첫 비-표 줄에서 멈추는지).
if ! grep -qF "이 문단은 표가 끝난 뒤라" <<<"$OUT"; then
  report "표 이후 본문은 색인에 미포함(추출 경계)" 0
else
  report "표 이후 본문은 색인에 미포함(추출 경계)" 1 "표 뒤 문단이 새어 들어왔습니다"
fi

# 3. frontmatter 의 description 한 줄이 스킬 소개로 실려야 한다.
if grep -qF "데모 스킬 설명 한 줄" <<<"$OUT"; then
  report "SKILL.md description 추출" 0
else
  report "SKILL.md description 추출" 1 "out=$OUT"
fi

# 4. 표가 없는 스킬은 그 사실을 명시해야 한다(조용히 빈칸으로 남기지 않음).
if grep -qF "라우팅 테이블 없음" <<<"$OUT"; then
  report "표 없는 스킬은 '라우팅 테이블 없음'으로 표기" 0
else
  report "표 없는 스킬은 '라우팅 테이블 없음'으로 표기" 1 "out=$OUT"
fi

# 5. 스킬마다 제목 절이 나와야 한다(스킬 순회 자체가 죽지 않았는지).
if grep -qE '^## demo$' <<<"$OUT" && grep -qE '^## plain$' <<<"$OUT"; then
  report "스킬별 제목 절 생성" 0
else
  report "스킬별 제목 절 생성" 1 "out=$OUT"
fi

# 6. 파일을 직접 쓰지 않고 stdout 으로만 낸다는 계약(헤더 주석). 이게 깨지면
#    prompt-lint 의 check_index_freshness 가 대조할 대상 자체가 사라진다.
if [ ! -e "$FAKE/contexts/INDEX.md" ]; then
  report "생성기가 INDEX.md 를 직접 쓰지 않음(stdout 전용)" 0
else
  report "생성기가 INDEX.md 를 직접 쓰지 않음(stdout 전용)" 1 "합성 트리에 INDEX.md 가 생성되었습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
