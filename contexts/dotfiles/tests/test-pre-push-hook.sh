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
HOOK="$REPO_ROOT/stow/git/.githooks/pre-push"
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
mkdir -p "$FIXTURE_REPO/bin/hooks" "$FIXTURE_REPO/bin/lib" \
  "$FIXTURE_REPO/contexts/aws/tests" "$FIXTURE_REPO/contexts/azure/tests" "$FIXTURE_REPO/contexts/dotfiles/tests"
cp "$REPO_ROOT/bin/hooks/run-suite.sh" "$FIXTURE_REPO/bin/hooks/run-suite.sh"
chmod +x "$FIXTURE_REPO/bin/hooks/run-suite.sh"
# run-suite.sh가 source하는 SSOT 라이브러리. 실제 배포 구조와 동일하게 상대 위치에 둔다.
cp "$REPO_ROOT/bin/lib/script-init.sh" "$FIXTURE_REPO/bin/lib/script-init.sh"

# run-suite.sh는 성공(rc=0) 시 [WARNING] 태그 없는 일반 stdout을 압축(억제)하므로,
# 이 스텁이 실제로 호출됐다는 증거는 run-suite.sh가 무조건 찍는 "-> [✓] <스크립트명>"
# 압축 로그 라인으로 확인한다(아래 테스트의 grep 대상). aws/azure 두 스킬을 모두 심어,
# "특정 스킬 경로만 건드리면 그 스킬만" vs "코어 로직을 건드리면 전체" 를 구분해서 검증한다.
# dotfiles 스텁도 함께 심는다: bin/linters, git 훅 본체, ansible 롤처럼 "코어도 아니고
# 특정 스킬 경로도 아닌" 변경이 dotfiles 스위트로 라우팅되는지(아래 1c) 확인하기 위함이다.
for SKILL_STUB in aws azure dotfiles; do
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

# 1c. bin/linters/* 는 위 코어 패턴(bin/lib, pre-flight-check.sh)에도, 스킬 전용 경로에도
#     안 걸린다. 그런데 이런 파일들(bin/linters/*, bin/utils/*, bin/hooks/run-suite.sh,
#     stow/git/.githooks/*, ansible/roles/*)은 전부 contexts/dotfiles/tests 에 전용 회귀
#     테스트가 있고 test-coverage-check.sh 가 그 존재를 하드 게이트로 강제한다. 그런데도
#     트리거 패턴에서 빠져 있어서, 고쳐도 push 시 아무 테스트가 돌지 않았다 — 커버리지는
#     강제하면서 실행은 안 하는 상태였다. dotfiles 스위트로 라우팅되는지 고정한다.
mkdir -p "$FIXTURE_REPO/bin/linters"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/linters/prompt-lint.sh"
git -C "$FIXTURE_REPO" add bin/linters/prompt-lint.sh
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(bin): 린터 판정 로직 수정"
LINTER_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $LINTER_SHA refs/heads/main $CORE_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/dotfiles/tests/run.sh" "$TMP/out" &&
  ! grep -qF "aws/tests/run.sh" "$TMP/out"; then
  report "linter-change (bin/linters 변경 시 dotfiles 스위트만 트리거)" 0
else
  report "linter-change (bin/linters 변경 시 dotfiles 스위트만 트리거)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 1d. git 훅 본체(stow/git/.githooks/*) 변경도 동일하게 dotfiles 스위트를 태워야 한다
#     (test-pre-commit-hook.sh / test-commit-msg-hook.sh / 이 파일 자신이 그 커버리지다).
mkdir -p "$FIXTURE_REPO/stow/git/.githooks"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/stow/git/.githooks/pre-commit"
git -C "$FIXTURE_REPO" add stow/git/.githooks/pre-commit
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(git): 커밋 훅 수정"
HOOKFILE_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $HOOKFILE_SHA refs/heads/main $LINTER_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/dotfiles/tests/run.sh" "$TMP/out"; then
  report "githook-change (git 훅 본체 변경 시 dotfiles 스위트 트리거)" 0
else
  report "githook-change (git 훅 본체 변경 시 dotfiles 스위트 트리거)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 1e. .github/scripts/* 는 ci.yml 이 "로컬 훅을 --no-verify 로 우회해도 막히는 최종
#     게이트"라고 선언한 곳이고, test-coverage-check.sh 도 이 디렉토리를 커버리지
#     하드 게이트 대상에 넣어 두었다(전용 스위트: test-lint-commit-messages.sh,
#     test-verify-bootstrap-env.sh). 그런데 트리거 패턴에는 빠져 있어 그 최종 게이트를
#     고쳐도 push 시 검증이 하나도 돌지 않았다(실측).
mkdir -p "$FIXTURE_REPO/.github/scripts"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/.github/scripts/lint-commit-messages.sh"
git -C "$FIXTURE_REPO" add .github/scripts/lint-commit-messages.sh
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(ci): 커밋 메시지 게이트 판정 수정"
CI_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $CI_SHA refs/heads/main $HOOKFILE_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/dotfiles/tests/run.sh" "$TMP/out"; then
  report "ci-script-change (.github/scripts 변경 시 dotfiles 스위트 트리거)" 0
else
  report "ci-script-change (.github/scripts 변경 시 dotfiles 스위트 트리거)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 1f. stow/ 는 예전에 stow/git/.githooks/* 로만 좁혀져 있어, 같은 디렉토리의
#     stow/zsh/.zshrc(test-zshrc-activation.sh 가 mise/fzf 활성화 블록을 검증)가
#     트리거 밖이었다. .githooks 가 아닌 stow 패키지 파일로 고정한다.
mkdir -p "$FIXTURE_REPO/stow/zsh"
echo "setopt AUTO_CD" >"$FIXTURE_REPO/stow/zsh/.zshrc"
git -C "$FIXTURE_REPO" add stow/zsh/.zshrc
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(zsh): 도구 활성화 블록 수정"
ZSHRC_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $ZSHRC_SHA refs/heads/main $CI_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/dotfiles/tests/run.sh" "$TMP/out"; then
  report "stow-package-change (stow/zsh 변경 시 dotfiles 스위트 트리거)" 0
else
  report "stow-package-change (stow/zsh 변경 시 dotfiles 스위트 트리거)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 1g. contexts/<skill>/examples/* 도 그 스킬의 회귀 스위트가 직접 돌리는 대상이다
#     (contexts/aiops/tests/run.sh 가 examples/anomaly-rag-pipeline.py 의 PII 마스킹을
#     실행해 검증한다). scripts/·tests/ 만 패턴에 있어 examples/ 의 마스킹 결함을 고쳐도
#     push 시 그 스킬 스위트가 돌지 않았다. 해당 스킬"만" 트리거되는지까지 고정한다.
mkdir -p "$FIXTURE_REPO/contexts/aws/examples"
echo 'print("x")' >"$FIXTURE_REPO/contexts/aws/examples/sample-pipeline.py"
git -C "$FIXTURE_REPO" add contexts/aws/examples/sample-pipeline.py
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(aws): 예제 파이프라인 마스킹 보강"
EXAMPLE_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

status=$(run_hook_with_refline "refs/heads/main $EXAMPLE_SHA refs/heads/main $ZSHRC_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/aws/tests/run.sh" "$TMP/out" &&
  ! grep -qF "azure/tests/run.sh" "$TMP/out"; then
  report "skill-examples-change (contexts/<skill>/examples 변경 시 해당 스킬만 트리거)" 0
else
  report "skill-examples-change (contexts/<skill>/examples 변경 시 해당 스킬만 트리거)" 1 "exit=$status out=$(cat "$TMP/out")"
fi

# 1h. bin/ 하위 스크립트는 "어느 스킬이 이걸 테스트하는가"가 경로에 드러나지 않는다.
#     예전엔 전부 dotfiles 스위트로 보냈는데, 실제 회귀 테스트는 스킬별로 흩어져 있다
#     (실측 매핑: bin/hooks/plugins/k8s-check.sh -> k8s + pre-flight-check,
#     bin/linters/idempotency-check.sh -> pre-flight-check 한 곳뿐,
#     bin/linters/prompt-lint.sh -> prompt-architect). 그래서 그 파일들을 고쳐도 정작
#     그것을 검증하는 스위트는 한 번도 돌지 않고 dotfiles 스위트만 초록불로 지나갔다
#     — test-coverage-check.sh 가 "회귀 테스트가 존재하는가"를 하드 게이트로 강제해 놓고
#     실행은 다른 곳을 돌리던 셈이다(실측: 플러그인 변경 -> "건드린 스킬: dotfiles" 한 줄).
#
#     이름으로 소유 스위트를 역추적하는지 고정한다. 픽스처의 aws 스위트에만 그 이름을
#     언급하는 테스트를 심어, "aws 는 돌고 azure 는 안 도는" 선택성까지 함께 본다
#     (무조건 전 스킬을 태우는 구현으로 바뀌어도 이 케이스가 깨지도록).
#     마커 파일(aws 스위트가 그 이름을 언급하는 테스트)은 반드시 "별도 커밋"으로 먼저
#     심는다. 같은 커밋에 넣으면 그 파일이 contexts/*/tests/* 케이스에 걸려 aws 를
#     독립적으로 트리거하므로, 역추적이 죽어도 이 케이스가 통과한다(실측: 역추적 호출을
#     add_skill dotfiles 로 되돌린 뮤테이션이 그대로 통과했다).
cat >"$FIXTURE_REPO/contexts/aws/tests/test-plugin-owner.sh" <<'EOF'
#!/usr/bin/env bash
# 이 스위트가 bin/hooks/plugins/k8s-check.sh 를 검증한다는 표시(역추적 대상).
exit 0
EOF
git -C "$FIXTURE_REPO" add contexts/aws/tests/test-plugin-owner.sh
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "test(aws): 플러그인 소유 표시 테스트 추가"
MARKER_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

mkdir -p "$FIXTURE_REPO/bin/hooks/plugins"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/hooks/plugins/k8s-check.sh"
git -C "$FIXTURE_REPO" add bin/hooks/plugins/k8s-check.sh
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "fix(k8s): 플러그인 판정 로직 수정"
PLUGIN_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

# 범위는 마커 커밋 이후로 잡아, 이 push 의 변경분이 bin/ 파일 하나뿐이 되게 한다.
status=$(run_hook_with_refline "refs/heads/main $PLUGIN_SHA refs/heads/main $MARKER_SHA")
if [ "$status" -eq 0 ] && grep -qF "[✓] contexts/aws/tests/run.sh" "$TMP/out" &&
  ! grep -qF "azure/tests/run.sh" "$TMP/out"; then
  report "bin-script-owner-lookup (bin/ 스크립트를 참조하는 스위트를 이름으로 역추적)" 0
else
  report "bin-script-owner-lookup (bin/ 스크립트를 참조하는 스위트를 이름으로 역추적)" 1 "exit=$status out=$(cat "$TMP/out")"
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
# idempotency:bypass (임시 픽스처에 대한 1회성 기록이라 상태 검증 불필요)
echo "무관한 변경" >>"$FIXTURE_REPO/README_UNRELATED.md"
git -C "$FIXTURE_REPO" add README_UNRELATED.md
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "docs: 무관한 문서 추가"
UNRELATED_SHA=$(git -C "$FIXTURE_REPO" rev-parse HEAD)

# 비교 기준은 직전 커밋(PLUGIN_SHA)이어야 한다. 더 앞을 기준으로 잡으면 그 사이의
# 1c~1h 커밋까지 범위에 들어와 "무관한 변경만" 이라는 전제가 깨진다.
# (케이스를 추가할 때는 이 기준 변수도 함께 옮길 것 — 체인이 끊기면 이 케이스가 대신 깨진다.)
status=$(run_hook_with_refline "refs/heads/main $UNRELATED_SHA refs/heads/main $PLUGIN_SHA")
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
