#!/usr/bin/env bash
# test-semantic-commit-lint.sh
#
# semantic-commit-lint.sh는 항상 exit 0(비차단 경고)이라 커밋을 막지 못하고, 5개 초과
# 파일이 3개 이상의 서로 다른 최상위 디렉토리(Context)에 걸쳐야만 경고를 낸다는 임계값
# 판정 로직이 있다. 이 임계값 계산(sort -u | grep -c) 이 깨져도 exit 코드로는 드러나지
# 않으므로 stderr 문구 유무로 판정 로직 자체를 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-semantic-commit-lint.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
LINT="$REPO_ROOT/bin/linters/semantic-commit-lint.sh"

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

echo "=== semantic-commit-lint.sh Atomic Commit 판정 로직 회귀 테스트 ==="

# 1. ok-baseline: 5개 파일이지만 전부 같은 최상위 디렉토리(aws) -> 경고 없어야 함.
status=0
out=$(bash "$LINT" aws/a.tf aws/b.tf aws/c.tf aws/d.tf aws/e.tf 2>&1) || status=$?
if [ "$status" -eq 0 ] && ! grep -qF "Atomic Commit 위반 가능성" <<<"$out"; then
  report "ok-single-context (같은 디렉토리 5개, 경고 없음)" 0
else
  report "ok-single-context (같은 디렉토리 5개, 경고 없음)" 1 "exit=$status out=$out"
fi

# 2. ok-boundary: 5개 파일이 정확히 2개 컨텍스트(aws, azure)에 걸침 -> 임계값(>2) 이내라 경고 없음.
status=0
out=$(bash "$LINT" aws/a.tf aws/b.tf aws/c.tf azure/d.tf azure/e.tf 2>&1) || status=$?
if [ "$status" -eq 0 ] && ! grep -qF "Atomic Commit 위반 가능성" <<<"$out"; then
  report "ok-two-contexts (경계값 2개 컨텍스트, 경고 없음)" 0
else
  report "ok-two-contexts (경계값 2개 컨텍스트, 경고 없음)" 1 "exit=$status out=$out"
fi

# 3. fail-scattered: 5개 파일이 3개 이상 컨텍스트(aws, azure, zsh)에 걸침 -> 경고 있어야 함(그러나 exit 0 유지).
status=0
out=$(bash "$LINT" aws/a.tf azure/b.tf zsh/.zshrc d.txt e.txt 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "Atomic Commit 위반 가능성" <<<"$out"; then
  report "fail-scattered (3개 이상 컨텍스트, 경고 있음 + 여전히 exit 0)" 0
else
  report "fail-scattered (3개 이상 컨텍스트, 경고 있음 + 여전히 exit 0)" 1 "exit=$status out=$out"
fi

# 3b. 임계값 바로 위 경계: 정확히 3개 컨텍스트. 위 3번은 ROOT(d.txt/e.txt)까지 세면
#     실제로는 4개 컨텍스트라, 임계값을 2에서 3으로 올려도 4 > 3 이 되어 여전히 경고가
#     떴다 — 즉 "2 초과" 라는 경계 자체는 검증되지 않고 있었다(뮤테이션으로 확인).
#     정확히 3개인 입력이 있어야 그 경계가 고정된다.
status=0
out=$(bash "$LINT" aws/a.tf aws/b.tf azure/c.tf azure/d.tf zsh/.zshrc 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "Atomic Commit 위반 가능성" <<<"$out"; then
  report "fail-exactly-three (정확히 3개 컨텍스트, 경고 있음)" 0
else
  report "fail-exactly-three (정확히 3개 컨텍스트, 경고 있음)" 1 "exit=$status out=$out"
fi

# 4. ok-few-files: 5개 미만이면 컨텍스트 수와 무관하게 애초에 검사 자체를 건너뛴다.
status=0
out=$(bash "$LINT" aws/a.tf azure/b.tf zsh/.zshrc d.txt 2>&1) || status=$?
if [ "$status" -eq 0 ] && ! grep -qF "Atomic Commit 위반 가능성" <<<"$out"; then
  report "ok-few-files (4개 이하는 검사 건너뜀)" 0
else
  report "ok-few-files (4개 이하는 검사 건너뜀)" 1 "exit=$status out=$out"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
