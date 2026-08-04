#!/usr/bin/env bash
# test-commit-msg-hook.sh
#
# git/.githooks/commit-msg는 bin/ 스캔 대상이 아니라 test-coverage-check.sh 게이트
# 밖에 있었고, 실제로 로직 결함(pre-commit의 BIN_REMINDERS 괄호 버그)이 회귀 테스트
# 없이 방치됐던 전례가 있다. Conventional Commits 정규식, merge/squash/fixup!/revert
# 예외 통과, 빈 메시지 처리라는 핵심 판정 분기를 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-commit-msg-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/git/.githooks/commit-msg"

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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_hook() {
  local msg=$1 source=${2:-} msgfile status=0
  msgfile="$TMP/MSG_$$_$RANDOM"
  printf '%s\n' "$msg" >"$msgfile"
  (cd "$TMP" && bash "$HOOK" "$msgfile" "$source") >"$TMP/out" 2>&1 || status=$?
  rm -f "$msgfile"
  echo "$status"
}

echo "=== commit-msg 훅 시맨틱 커밋 판정 로직 회귀 테스트 ==="

# 1. 정상 conventional commit -> exit 0
status=$(run_hook "feat(aws): EKS 노드그룹 오토스케일링 정책 추가")
if [ "$status" -eq 0 ]; then
  report "ok-conventional (정상 형식, exit 0)" 0
else
  report "ok-conventional (정상 형식, exit 0)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 2. 컨벤션 위반 -> exit 1 + 안내 문구 포함
status=$(run_hook "fixed the bug")
if [ "$status" -eq 1 ] && grep -qF "시맨틱 커밋 컨벤션 위반" "$TMP/out"; then
  report "fail-non-conventional (컨벤션 위반, exit 1 + 안내)" 0
else
  report "fail-non-conventional (컨벤션 위반, exit 1 + 안내)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 3. type만 있고 콜론 뒤 본문이 없으면 위반 -> exit 1
status=$(run_hook "feat: ")
if [ "$status" -eq 1 ]; then
  report "fail-empty-subject (본문 없는 콜론, exit 1)" 0
else
  report "fail-empty-subject (본문 없는 콜론, exit 1)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 4. merge 소스는 컨벤션 위반 메시지라도 통과해야 한다.
status=$(run_hook "Merge branch 'feature/x' into main" "merge")
if [ "$status" -eq 0 ]; then
  report "ok-merge-source (merge 소스는 그대로 통과)" 0
else
  report "ok-merge-source (merge 소스는 그대로 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 5. squash 소스도 동일하게 통과해야 한다.
status=$(run_hook "Squashed commit of the following:" "squash")
if [ "$status" -eq 0 ]; then
  report "ok-squash-source (squash 소스는 그대로 통과)" 0
else
  report "ok-squash-source (squash 소스는 그대로 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 6. rebase --autosquash 대상(fixup!)은 컨벤션 형식이 아니어도 통과해야 한다.
status=$(run_hook "fixup! feat(aws): EKS 노드그룹 오토스케일링 정책 추가")
if [ "$status" -eq 0 ]; then
  report "ok-fixup-prefix (fixup! 접두사는 통과)" 0
else
  report "ok-fixup-prefix (fixup! 접두사는 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 7. git revert 자동 생성 메시지도 통과해야 한다.
status=$(run_hook 'Revert "feat(aws): EKS 노드그룹 오토스케일링 정책 추가"')
if [ "$status" -eq 0 ]; then
  report 'ok-revert-prefix (Revert "..." 는 통과)' 0
else
  report 'ok-revert-prefix (Revert "..." 는 통과)' 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 8. 주석/빈 줄만 있는 메시지(빈 커밋 메시지)는 git 자체 검증에 맡기고 통과해야 한다.
status=$(run_hook $'# comment only\n')
if [ "$status" -eq 0 ]; then
  report "ok-empty-message (주석뿐인 빈 메시지, exit 0)" 0
else
  report "ok-empty-message (주석뿐인 빈 메시지, exit 0)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
