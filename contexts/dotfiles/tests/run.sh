#!/usr/bin/env bash
# dotfiles 스킬 회귀 테스트 진입점
#
# 이 스킬은 검증 대상이 둘(setup.sh, prompt-lint.sh)이고 각각 픽스처 구성이 전혀
# 달라, 케이스를 파일로 나누고 여기서 순차 실행한다. pre-commit 훅은 tests/run.sh
# 하나만 호출하므로 진입점은 그대로 유지된다.
#
# 한 스위트가 실패해도 나머지를 계속 실행한다. 먼저 실패한 쪽만 보고 끝내면
# 나머지 스위트의 상태를 다음 실행까지 알 수 없다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=()
for suite in setup-idempotency prompt-lint; do
  bash "$TESTS_DIR/$suite.sh" || FAILED+=("$suite")
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "실패한 스위트: ${FAILED[*]}"
  exit 1
fi
echo "dotfiles 회귀 테스트 전체 통과"
