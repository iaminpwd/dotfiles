#!/usr/bin/env bash
# test-pre-push-hook.sh
#
# git/.githooks/pre-push는 bin/*.sh 와 달리 test-coverage-check.sh 게이트 밖에 있어
# collect_changed_skills_from_range()의 스킬 매핑 로직(어떤 변경분이 어떤 contexts/<skill>
# 회귀 스위트를 트리거하는지)이 깨져도 아무 것도 잡아주지 못했다. 실제 무거운 외부
# 도구(checkov/tflint 등)를 타지 않도록, 대상 스킬의 tests/run.sh를 exit 0 스텁으로
# 대체해 오케스트레이션 로직(범위 판정 + 실제 스텁 호출 여부)만 격리해서 검증한다.
# run-suite.sh 자체의 정확성은 contexts/dotfiles/tests/test-run-suite.sh가
# 별도로 담당하므로, 이 스위트는 실제 run-suite.sh를 그대로 가져와 정상 경로(1차
# 분기)를 그대로 태운다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-pre-push-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/git/.githooks/pre-push"
ZERO_SHA="0000000000000000000000000000000000000000"

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

# 픽스처 저장소 구성: basename이 "dotfiles"여야 훅이 활성화되고(line 22 가드),
# 실제 run-suite.sh를 그대로 가져와 아래 aws 스텁만 호출시킨다.
FIXTURE_REPO="$TMP/dotfiles"
mkdir -p "$FIXTURE_REPO/bin/hooks" "$FIXTURE_REPO/bin/lib" "$FIXTURE_REPO/contexts/aws/tests" "$FIXTURE_REPO/contexts/azure/tests"
cp "$REPO_ROOT/bin/hooks/run-suite.sh" "$FIXTURE_REPO/bin/hooks/run-suite.sh"
chmod +x "$FIXTURE_REPO/bin/hooks/run-suite.sh"
# run-suite.sh가 source하는 SSOT 라이브러리. 실제 배포 구조와 동일하게 상대 위치에 둔다.
cp "$REPO_ROOT/bin/lib/script-init.sh" "$FIXTURE_REPO/bin/lib/script-init.sh"

# run-suite.sh는 성공(rc=0) 시 [WARNING] 태그 없는 일반 stdout을 압축(억제)하므로,
# 이 스텁이 실제로 호출됐다는 증거는 run-suite.sh가 무조건 찍는 "-> [✓] <스크립트명>"
# 압축 로그 라인으로 확인한다(아래 테스트의 grep 대상). aws/azure 두 스킬을 모두 심어,
# "특정 스킬 경로만 건드리면 그 스킬만" vs "코어 로직을 건드리면 전체" 를 구분해서 검증한다.
for SKILL_STUB in aws azure; do
  cat >"$FIXTURE_REPO/contexts/$SKILL_STUB/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FIXTURE_REPO/contexts/$SKILL_STUB/tests/run.sh"
done

git -C "$FIXTURE_REPO" init -q
git -C "$FIXTURE_REPO" config user.email "test@example.com"
git -C "$FIXTURE_REPO" config user.name "Test"
git -C "$FIXTURE_REPO" add -A
# 이 샌드박스는 core.hooksPath가 전역으로 이 저장소의 git/.githooks를 가리켜, 격리
# 없이 커밋하면 셋업 중에 실제 훅이 재귀적으로 발동한다(test-pre-commit-hook.sh와
# 동일 이유). 테스트 대상 SUT와 무관한 셋업 커밋이므로 훅을 꺼서 격리한다.
BASE_SHA=$(git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "chore: 초기 베이스 커밋" && git -C "$FIXTURE_REPO" rev-parse HEAD)

echo "=== pre-push 훅 스킬 회귀 스위트 트리거 로직 회귀 테스트 ==="

run_hook_with_refline() {
  local refline=$1 status=0
  (cd "$FIXTURE_REPO" && printf '%s\n' "$refline" | bash "$HOOK") >"$TMP/out" 2>&1 || status=$?
  echo "$status"
}

# 1. aws 스킬 소스(contexts/aws/scripts/*)를 건드린 커밋을 기존 브랜치에 push하면,
#    aws 스킬이 감지되어 그 스텁 run.sh가 실제로 호출돼야 한다.
mkdir -p "$FIXTURE_REPO/contexts/aws/scripts"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/contexts/aws/scripts/deploy-check.sh"
git -C "$FIXTURE_REPO" add contexts/aws/scripts/deploy-check.sh
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "feat(aws): 배포 점검 스크립트 추가"
NEW_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $NEW_SHA refs/heads/main $BASE_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/aws/tests/run.sh" "$TMP/out" && ! grep -qF "azure/tests/run.sh" "$TMP/out"; then
  report "detect-and-run-aws (aws만 감지 + 스텁 실제 호출, azure는 미실행)" 0
else
  report "detect-and-run-aws (aws만 감지 + 스텁 실제 호출, azure는 미실행)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 1b. bin/lib/*(모든 스킬이 공유하는 코어 검증 로직) 변경은 경로 패턴이 특정 스킬 하나에
#     매핑되지 않으므로, 존재하는 스킬 회귀 스위트 전부(aws + azure)를 대상으로 삼아야 한다.
mkdir -p "$FIXTURE_REPO/bin/lib"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/lib/pfc-iac-checks.sh"
git -C "$FIXTURE_REPO" add bin/lib/pfc-iac-checks.sh
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(bin): 코어 IaC 검증 로직 수정"
CORE_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $CORE_SHA refs/heads/main $NEW_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/aws/tests/run.sh" "$TMP/out" && grep -qF "[✓] contexts/azure/tests/run.sh" "$TMP/out"; then
  report "core-lib-change (bin/lib 변경 시 존재하는 스킬 전체 감지)" 0
else
  report "core-lib-change (bin/lib 변경 시 존재하는 스킬 전체 감지)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 2. 새 브랜치 최초 push(remote_sha=0000...)도 동일하게 감지되어야 한다(EMPTY_TREE 비교 분기).
status=$(run_hook_with_refline "refs/heads/feature $NEW_SHA refs/heads/feature $ZERO_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/aws/tests/run.sh" "$TMP/out"; then
  report "new-branch-push (신규 브랜치 push도 EMPTY_TREE 기준으로 감지)" 0
else
  report "new-branch-push (신규 브랜치 push도 EMPTY_TREE 기준으로 감지)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 3. 어떤 스킬 패턴에도 안 걸리는 무관한 변경만 push하면, 회귀 스위트를 아예 실행하지
#    않고(스텁 마커 없음) 조용히 exit 0이어야 한다(오탐 방지 + 불필요한 실행 방지).
echo "무관한 변경" >>"$FIXTURE_REPO/README_UNRELATED.md"
git -C "$FIXTURE_REPO" add README_UNRELATED.md
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "docs: 무관한 문서 추가"
UNRELATED_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $UNRELATED_SHA refs/heads/main $CORE_SHA")
if [ "$status" -eq 0 ] && [ ! -s "$TMP/out" ]; then
  report "no-skill-match (무관한 변경은 회귀 스위트 미실행 + exit 0)" 0
else
  report "no-skill-match (무관한 변경은 회귀 스위트 미실행 + exit 0)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 4. 브랜치 삭제 push(local_sha=0000...)는 대상이 없으므로 무조건 조용히 exit 0이어야 한다.
status=$(run_hook_with_refline "refs/heads/old-branch $ZERO_SHA refs/heads/old-branch $NEW_SHA")
if [ "$status" -eq 0 ] && [ ! -s "$TMP/out" ]; then
  report "branch-delete-push (브랜치 삭제 push는 무동작 + exit 0)" 0
else
  report "branch-delete-push (브랜치 삭제 push는 무동작 + exit 0)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 5. 저장소 basename이 "dotfiles"가 아니면(전역 훅이 dotfiles 밖 임의 저장소에서
#    실행되는 경우) 즉시 조용히 통과해야 한다(dotfiles 전용 스킬 구조 오탐 방지).
OTHER_REPO="$TMP/some-other-repo"
mkdir -p "$OTHER_REPO"
git -C "$OTHER_REPO" init -q
git -C "$OTHER_REPO" config user.email "test@example.com"
git -C "$OTHER_REPO" config user.name "Test"
echo x >"$OTHER_REPO/a.txt"
git -C "$OTHER_REPO" add a.txt
OTHER_SHA=$(git -C "$OTHER_REPO" -c core.hooksPath=/dev/null commit -q -m "chore: 초기 커밋" && git -C "$OTHER_REPO" rev-parse HEAD)
status=0
(cd "$OTHER_REPO" && printf '%s\n' "refs/heads/main $OTHER_SHA refs/heads/main $ZERO_SHA" | bash "$HOOK") >"$TMP/out2" 2>&1 || status=$?
if [ "$status" -eq 0 ] && [ ! -s "$TMP/out2" ]; then
  report "non-dotfiles-repo (dotfiles 밖 저장소는 즉시 무동작 통과)" 0
else
  report "non-dotfiles-repo (dotfiles 밖 저장소는 즉시 무동작 통과)" 1 "exit=$status out=$(cat "$TMP/out2")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
