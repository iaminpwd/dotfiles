#!/usr/bin/env bash
# 임시 저장소에서 실제 선택기와 러너를 실행해 선택 범위·중복 제거·실패 전파를 검증한다.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo space"
mkdir -p "$REPO/bin/hooks" "$REPO/bin/lib" "$REPO/bin/utils" "$REPO/contexts/dotfiles/tests"
cp "$ROOT/bin/hooks/stop-regression-check.sh" "$ROOT/bin/hooks/run-suite.sh" "$REPO/bin/hooks/"
cp "$ROOT/bin/lib/script-init.sh" "$REPO/bin/lib/"
git -C "$REPO" init -q
git -C "$REPO" config user.name Test
git -C "$REPO" config user.email test@example.com
for name in safe-link-backup merge-agent-hooks stop-regression-check; do
  printf '#!/usr/bin/env bash\necho "TEST %s"\n' "$name" >"$REPO/contexts/dotfiles/tests/test-$name.sh"
done
printf '#!/bin/bash\n' >"$REPO/bin/utils/safe-link-backup.sh"
printf '#!/bin/bash\n' >"$REPO/bin/utils/merge-agent-hooks.sh"
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'chore: 테스트 초기 상태'
RUNNER="$REPO/bin/hooks/stop-regression-check.sh"

printf '# 수정\n' >>"$REPO/bin/utils/safe-link-backup.sh"
git -C "$REPO" add bin/utils/safe-link-backup.sh
printf '# 추가 수정\n' >>"$REPO/bin/utils/safe-link-backup.sh"
selected=$(bash "$RUNNER" --list)
[ "$selected" = "$REPO/contexts/dotfiles/tests/test-safe-link-backup.sh" ]
echo 'PASS: staged·unstaged 중복 제거, 관련 테스트만 선택'

printf '# 새 변경\n' >"$REPO/contexts/dotfiles/tests/test-new.sh"
selected=$(bash "$RUNNER" --list)
[[ "$selected" == *test-new.sh* && "$selected" != *test-merge-agent-hooks.sh* ]]
echo 'PASS: untracked 테스트도 선택, 무관한 테스트는 제외'

mkdir -p "$REPO/contexts/observability/scripts"
printf '# 정책 수정\n' >"$REPO/contexts/observability/scripts/validate-alert-rules.sh"
selected=$(bash "$RUNNER" --list)
[[ "$selected" != *observability* ]]
echo 'PASS: 도메인 정책 스위트는 기본 Stop 대상에서 제외'

# 성공 여부를 꾸미는 대신 실제 러너가 선택된 테스트의 실패를 받아야 한다.
printf '#!/usr/bin/env bash\necho REGRESSION_FAILURE\nexit 7\n' >"$REPO/contexts/dotfiles/tests/test-safe-link-backup.sh"
if bash "$RUNNER" >"$TMP/output" 2>&1; then
  echo 'FAIL: 회귀 실패가 통과 처리됨'
  exit 1
fi
grep -q REGRESSION_FAILURE "$TMP/output"
grep -q '재현 명령' "$TMP/output"
grep -q 'test-safe-link-backup.sh' "$TMP/output"
echo 'PASS: 회귀 실패와 개별 재현 명령 전달'

# 문서만 바뀐 저장소에서는 회귀 테스트를 실행하지 않는다.
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'chore: 테스트 상태 저장'
printf '# 문서만 변경\n' >"$REPO/README.md"
[ -z "$(bash "$RUNNER" --list)" ]
bash "$RUNNER"
echo 'PASS: 문서만 변경하면 핵심 회귀 실행 없음'
