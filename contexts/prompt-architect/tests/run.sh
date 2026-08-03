#!/usr/bin/env bash
# prompt-architect 스킬 회귀 테스트 진입점
#
# 사용: bash ~/dotfiles/contexts/prompt-architect/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=()
for suite in test_prompt_lint test-record-provenance; do
  bash "$TESTS_DIR/$suite.sh" || FAILED+=("$suite")
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "실패한 스위트: ${FAILED[*]}"
  exit 1
fi
echo "prompt-architect 회귀 테스트 전체 통과"
