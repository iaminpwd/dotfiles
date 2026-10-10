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
for name in safe-link-backup stow-toctou merge-agent-hooks stop-regression-check; do
  printf '#!/usr/bin/env bash\necho "TEST %s"\n' "$name" >"$REPO/contexts/dotfiles/tests/test-$name.sh"
done
printf '#!/bin/bash\n' >"$REPO/bin/utils/safe-link-backup.sh"
printf '#!/bin/bash\n' >"$REPO/bin/utils/merge-agent-hooks.sh"
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'chore: 테스트 초기 상태'
RUNNER="$REPO/bin/hooks/stop-regression-check.sh"

printf '#!/bin/bash\n# 수정\n' >"$REPO/bin/utils/safe-link-backup.sh"
git -C "$REPO" add bin/utils/safe-link-backup.sh
# idempotency:bypass (매 실행 새 mktemp Git fixture에서 staged 이후 unstaged 변경을 합성하는 1회성 append)
printf '# 추가 수정\n' >>"$REPO/bin/utils/safe-link-backup.sh"
selected=$(bash "$RUNNER" --list)
[ "$selected" = "$REPO/contexts/dotfiles/tests/test-safe-link-backup.sh" ]
echo 'PASS: staged·unstaged 중복 제거, 관련 테스트만 선택'

# Shell wrapper delegates its backup safety to this Python helper. A helper
# change must route back to the same regression suite in Stop checks.
printf '# helper changed\n' >"$REPO/bin/utils/safe-link-backup.py"
selected=$(bash "$RUNNER" --list)
[ "$selected" = "$REPO/contexts/dotfiles/tests/test-safe-link-backup.sh" ]
echo 'PASS: 백업 Python 헬퍼 수정도 safe-link 회귀로 라우팅'

# macOS 기본 BSD readlink처럼 -f가 없는 PATH에서도 selector 자체가 시작되어야 한다.
# Stop gate가 이 스크립트를 호출하므로 여기서 시작 실패하면 변경 영역 회귀가 통째로 빠진다.
BSD_BIN="$TMP/bsd-bin"
mkdir -p "$BSD_BIN"
cat >"$BSD_BIN/readlink" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-f" ]; then
  echo 'readlink: illegal option -- f' >&2
  exit 1
fi
exec /usr/bin/readlink "$@"
STUB
chmod +x "$BSD_BIN/readlink"

status=0
selected=$(PATH="$BSD_BIN:$PATH" bash "$RUNNER" --list 2>"$TMP/bsd-readlink.err") || status=$?
if [ "$status" -eq 0 ] &&
  [ "$selected" = "$REPO/contexts/dotfiles/tests/test-safe-link-backup.sh" ] &&
  ! grep -qF 'readlink: illegal option -- f' "$TMP/bsd-readlink.err"; then
  echo 'PASS: BSD readlink 환경에서도 변경 영역 회귀 선택기 실행'
else
  echo "FAIL: BSD readlink 환경에서 selector 시작 실패 (exit=$status)" >&2
  cat "$TMP/bsd-readlink.err" >&2
  printf '%s\n' "$selected" >&2
  exit 1
fi

printf '# stow helper changed\n' >"$REPO/bin/utils/stow-safe-backup.py"
selected=$(bash "$RUNNER" --list)
[[ "$selected" == *test-stow-toctou.sh* ]]
echo 'PASS: Stow Python 백업 헬퍼 변경은 TOCTOU 회귀로 라우팅'

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

# ai_agent role 변경 시 현재 존재하는 회귀 스위트만 선택해야 한다. 예전에 global
# script collision 검사를 제거했는데 selector에 test-check-agent-collision이 남아 있으면
# role을 건드리는 순간 존재하지 않는 테스트 때문에 Stop 검증이 하드 실패한다.
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'chore: ai agent fixture 준비'
mkdir -p "$REPO/ansible/roles/ai_agent/tasks"
for name in agent-batch-backup safe-link-backup merge-agent-hooks prune-orphan-skills; do
  printf '#!/usr/bin/env bash\necho "TEST %s"\n' "$name" >"$REPO/contexts/dotfiles/tests/test-$name.sh"
done
printf '%s\n' '---' '- name: fixture' >"$REPO/ansible/roles/ai_agent/tasks/main.yml"
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'chore: ai agent baseline'
printf '%s\n' '---' '- name: fixture' '# 수정' >"$REPO/ansible/roles/ai_agent/tasks/main.yml"

status=0
selected=$(bash "$RUNNER" --list 2>"$TMP/ai-agent.err") || status=$?
if [ "$status" -eq 0 ] &&
  [[ "$selected" == *test-agent-batch-backup.sh* ]] &&
  [[ "$selected" == *test-safe-link-backup.sh* ]] &&
  [[ "$selected" == *test-merge-agent-hooks.sh* ]] &&
  [[ "$selected" == *test-prune-orphan-skills.sh* ]] &&
  [[ "$selected" != *test-check-agent-collision.sh* ]]; then
  echo 'PASS: ai_agent role 변경은 현재 존재하는 회귀 스위트만 선택'
else
  echo "FAIL: ai_agent role selector가 삭제된 회귀를 참조함 (exit=$status)"
  cat "$TMP/ai-agent.err" >&2
  printf '%s\n' "$selected" >&2
  exit 1
fi

# 문서만 바뀐 저장소에서는 회귀 테스트를 실행하지 않는다.
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'chore: 테스트 상태 저장'
printf '# 문서만 변경\n' >"$REPO/README.md"
[ -z "$(bash "$RUNNER" --list)" ]
bash "$RUNNER"
echo 'PASS: 문서만 변경하면 핵심 회귀 실행 없음'
