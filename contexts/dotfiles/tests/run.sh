#!/usr/bin/env bash
# dotfiles 스킬 회귀 테스트 진입점
#
# 현재 스킬의 회귀 테스트 스위트들을 여기서 순차 실행한다.
# 한 스위트가 실패해도 나머지를 계속 실행하여 전체 상태를 확인한다.
#
# 한 스위트가 실패해도 나머지를 계속 실행한다. 먼저 실패한 쪽만 보고 끝내면
# 나머지 스위트의 상태를 다음 실행까지 알 수 없다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=()
for suite in check-symlinks test-detector-logic test-ansible test-agent-edits-hook test-semantic-commit-lint test-check-agent-collision test-merge-agent-hooks test-stow-backup test-git-relpath test-jq-resolve test-commit-msg-hook test-pre-commit-hook test-pre-push-hook test-test-coverage-check; do
  bash "$TESTS_DIR/$suite.sh" || FAILED+=("$suite")
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "실패한 스위트: ${FAILED[*]}"
  exit 1
fi
echo "dotfiles 회귀 테스트 전체 통과"
