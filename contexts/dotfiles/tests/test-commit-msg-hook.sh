#!/usr/bin/env bash
# test-commit-msg-hook.sh
#
# stow/git/.githooks/commit-msg는 bin/ 스캔 대상이 아니라 test-coverage-check.sh 게이트
# 밖에 있었고, 실제로 로직 결함(pre-commit의 BIN_REMINDERS 괄호 버그)이 회귀 테스트
# 없이 방치됐던 전례가 있다. Conventional Commits 정규식, merge/squash/fixup!/revert
# 예외 통과, 빈 메시지 처리라는 핵심 판정 분기를 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-commit-msg-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/stow/git/.githooks/commit-msg"

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

# -----------------------------------------------------------------------------
# 9~11. git 이 실제로 훅을 호출하는 경로
# -----------------------------------------------------------------------------
# 위 1~8 은 run_hook 이 $2(source)를 직접 넘겨 검증한다. 그런데 git 은 commit-msg 훅에
# 메시지 파일 경로($1) 하나만 넘기고 $2 를 주지 않는다($2 를 받는 것은 prepare-commit-msg
# 훅이다). 즉 4·5 번(merge/squash 면제)이 검증하던 조건은 .github/scripts/
# lint-commit-messages.sh(CI 재검증, 훅을 직접 호출하며 source 를 명시)에서만 성립하고
# 실제 커밋 경로에서는 한 번도 성립하지 않았다 — 그 결과 `git merge --no-ff` 가 자동 생성
# 메시지 때문에 "컨벤션 위반"으로 차단되는 버그가 8/8 통과 상태로 존속했다(실측 재현).
# 그래서 아래는 인자를 손으로 만들지 않고 git 이 직접 훅을 부르게 해 검증한다.
#
# 훅 격리: commit-msg 하나만 담은 전용 디렉토리를 저장소 로컬 core.hooksPath 로 지정한다.
# .git/hooks/ 에 심볼릭 링크를 두는 방식은 쓸 수 없다 — 이 테스트는 전역 core.hooksPath 가
# 이미 이 저장소의 git/.githooks 를 가리키는 환경에서 돌고(test-pre-commit-hook.sh 의 같은
# 지점 주석 참조), core.hooksPath 가 설정돼 있으면 git 은 .git/hooks/ 를 통째로 무시한다.
# 그러면 (1) 검증 대상이 SUT($HOOK, 워킹트리 사본)가 아니라 배포된 훅이 되어 둘이 갈렸을 때
# 테스트가 그 사실을 못 잡고, (2) 같은 디렉토리의 pre-commit(trufflehog 스캔)까지 매 커밋마다
# 딸려와 느려지고 출력이 오염된다(실측: 이 블록 최초 작성 시 두 증상 다 재현).
GIT_FIXTURE="$TMP/gitrepo"
HOOKS_ONLY="$TMP/hooks-commit-msg-only"
mkdir -p "$GIT_FIXTURE" "$HOOKS_ONLY"
ln -sf "$HOOK" "$HOOKS_ONLY/commit-msg"
git -C "$GIT_FIXTURE" init -q
git -C "$GIT_FIXTURE" config user.email "test@example.com"
git -C "$GIT_FIXTURE" config user.name "Test"
git -C "$GIT_FIXTURE" config core.hooksPath "$HOOKS_ONLY"

echo "base" >"$GIT_FIXTURE/base.txt"
git -C "$GIT_FIXTURE" add base.txt
git -C "$GIT_FIXTURE" commit -q -m "feat: 초기 커밋"
BASE_BRANCH=$(git -C "$GIT_FIXTURE" rev-parse --abbrev-ref HEAD)

# 9. 진짜 머지 커밋: git 자동 생성 메시지("Merge branch ...")가 통과해야 한다.
git -C "$GIT_FIXTURE" checkout -q -b topic
echo "t" >"$GIT_FIXTURE/topic.txt"
git -C "$GIT_FIXTURE" add topic.txt
git -C "$GIT_FIXTURE" commit -q -m "feat: 토픽 변경"
git -C "$GIT_FIXTURE" checkout -q "$BASE_BRANCH"
echo "m" >"$GIT_FIXTURE/main.txt"
git -C "$GIT_FIXTURE" add main.txt
git -C "$GIT_FIXTURE" commit -q -m "feat: 본선 변경"

status=0
git -C "$GIT_FIXTURE" merge --no-ff topic >"$TMP/out" 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-real-git-merge (실제 git merge 자동 메시지가 통과)" 0
else
  report "ok-real-git-merge (실제 git merge 자동 메시지가 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 10. 스쿼시 머지 대기 상태(SQUASH_MSG 존재)에서의 커밋도 통과해야 한다.
git -C "$GIT_FIXTURE" checkout -q -b topic2
echo "t2" >"$GIT_FIXTURE/topic2.txt"
git -C "$GIT_FIXTURE" add topic2.txt
git -C "$GIT_FIXTURE" commit -q -m "feat: 토픽2 변경"
git -C "$GIT_FIXTURE" checkout -q "$BASE_BRANCH"
git -C "$GIT_FIXTURE" merge --squash topic2 >/dev/null 2>&1
status=0
git -C "$GIT_FIXTURE" commit -q -m "Squashed commit of the following:" >"$TMP/out" 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-real-git-squash (SQUASH_MSG 대기 상태의 커밋이 통과)" 0
else
  report "ok-real-git-squash (SQUASH_MSG 대기 상태의 커밋이 통과)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 11. 면제가 과하지 않은지: 머지/스쿼시 상태가 아닌 평범한 커밋은 git 경로에서도 막혀야 한다.
#     9·10 을 통과시키려고 판정을 넓히면 이 검사가 먼저 깨진다.
echo "plain" >"$GIT_FIXTURE/plain.txt"
git -C "$GIT_FIXTURE" add plain.txt
status=0
git -C "$GIT_FIXTURE" commit -q -m "그냥 커밋" >"$TMP/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] && grep -qF "시맨틱 커밋 컨벤션 위반" "$TMP/out"; then
  report "fail-real-git-plain (평상시 커밋은 git 경로에서도 차단)" 0
else
  report "fail-real-git-plain (평상시 커밋은 git 경로에서도 차단)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
