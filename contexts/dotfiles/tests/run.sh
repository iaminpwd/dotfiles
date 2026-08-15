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

# [주의] 이 디렉토리의 test-*.sh 는 아래 목록에 빠짐없이 등록돼야 한다. 등록을 빠뜨려도
# test-coverage-check.sh 의 하드 게이트는 "스크립트 이름이 tests/ 어딘가에 언급되는가"만
# 보므로 그대로 초록불이 뜬다 — 즉 커버리지 게이트가 누락을 잡아주지 못한다(실측:
# test-pre-flight-live-hook / test-pre-flight-gate-hook 이 등록 누락 상태로 just test /
# pre-push / CI 어디서도 실행되지 않았는데 커버리지는 통과였다).
# 대조: bash -c 'for t in contexts/dotfiles/tests/test-*.sh; do grep -q "$(basename "$t" .sh)" contexts/dotfiles/tests/run.sh || echo "미등록: $t"; done'
#
# check-symlinks 는 이 목록에 없다(파일 자체는 진단용으로 남겨둠).
# 그 스위트는 broken-symlink-detector.sh 를 인자 없이 불러 개발자의 실제 $HOME 을
# depth 2 까지 훑는데, dotfiles 와 아무 상관 없는 끊긴 링크 하나만 있어도 exit 1 이라
# 회귀 스위트 전체가(따라서 just test / pre-push / CI 가) 환경 탓으로 실패했다.
# 판정 로직 자체는 바로 다음의 test-detector-logic 이 격리된 픽스처로 이미 검증한다.
# 지금 이 머신의 홈 상태를 보고 싶으면 직접 실행할 것:
#   bash contexts/dotfiles/tests/check-symlinks.sh
FAILED=()
for suite in test-detector-logic test-ansible test-agent-edits-hook test-semantic-commit-lint test-check-agent-collision test-merge-agent-hooks test-stow-backup test-safe-link-backup test-prune-orphan-skills test-git-relpath test-jq-resolve test-tool-probe-ssot test-script-init test-plugin-targets test-run-suite test-pre-flight-live-hook test-pre-flight-gate-hook test-commit-msg-hook test-pre-commit-hook test-pre-push-hook test-test-coverage-check test-zshrc-activation test-lint-commit-messages test-verify-bootstrap-env test-install-mise; do
  bash "$TESTS_DIR/$suite.sh" || FAILED+=("$suite")
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "실패한 스위트: ${FAILED[*]}"
  exit 1
fi
echo "dotfiles 회귀 테스트 전체 통과"
