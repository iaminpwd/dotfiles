#!/usr/bin/env bash
# dotfiles 스킬 회귀 테스트 진입점
#
# 등록된 회귀 테스트를 순차 실행하되, 실패해도 나머지 검증을 끝까지 수행한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# [주의] 이 디렉토리의 test-*.sh 는 아래 목록에 빠짐없이 등록돼야 한다. 등록 누락은
# test-coverage-check.sh 의 "회귀 스위트 등록 누락 하드 게이트"가 차단한다 — 파일은 있는데
# run.sh 목록에 없으면 exit 1 로 이름을 지목한다(실측 확인). 그 게이트는
# test-pre-flight-gate-hook 이 등록 누락 상태로 just test /
# pre-push / CI 어디서도 실행되지 않았던 사고 이후에 추가됐고, 전용 회귀 테스트도 있다
# (test-test-coverage-check.sh 의 registered-suite-passes / comment-only-mention-blocks 등).
# 손으로 대조할 필요는 없다.
#
# broken-symlink-detector.sh 는 개발자의 실제 $HOME 을 depth 5 까지 훑는 수동 진단
# 도구라 이 회귀 runner에서는 실행하지 않는다. dotfiles 와 무관한 끊긴 링크 하나만 있어도
# 전체 회귀가 환경 탓으로 실패하기 때문이다. 탐지 로직 자체는 test-detector-logic이
# 격리된 HOME 픽스처로 검증한다. 현재 머신의 홈 상태를 보고 싶으면 직접 실행할 것:
#   bash bin/utils/broken-symlink-detector.sh
FAILED=()
for suite in \
  test-zsh-updates \
  test-zsh-supply-chain \
  test-zsh-check-mode \
  test-zsh-privilege-path \
  test-zsh-shell-failure \
  test-fresh-docker-session \
  test-setup-behavior \
  test-justfile \
  test-ci-tool-config \
  test-ci-secret-history \
  test-bootstrap-changes \
  test-bootstrap-idempotency-gate \
  test-tflint-init \
  test-tflint-interrupted-install \
  test-detector-logic \
  test-dead-legacy-aiexclude \
  test-docs-aiexclude-consistency \
  test-ansible \
  test-agent-edits-hook \
  test-semantic-commit-lint \
  test-merge-agent-hooks \
  test-fresh-install-agent-hooks \
  test-stow-backup \
  test-stow-legacy-mise-link \
  test-stow-drift-portability \
  test-stow-real-failure \
  test-stow-real-unlink \
  test-stow-ignore \
  test-stow-toctou \
  test-safe-link-backup \
  test-agent-batch-backup \
  test-agent-script-update-prune \
  test-prune-orphan-skills \
  test-git-relpath \
  test-jq-resolve \
  test-tool-probe-ssot \
  test-script-init \
  test-plugin-targets \
  test-run-suite \
  test-pre-flight-gate-hook \
  test-stop-regression-check \
  test-commit-msg-hook \
  test-pre-commit-hook \
  test-pre-push-hook \
  test-test-coverage-check \
  test-zshrc-activation \
  test-zshenv-path \
  test-lint-commit-messages \
  test-verify-bootstrap-env \
  test-install-mise \
  test-renovate-mise-self-pin \
  test-generate-context-index; do
  # CI-only diagnostic. Avoid output changes unless a caller requests timings.
  if [ -n "${DOTFILES_SUITE_TIMING_LOG:-}" ]; then
    started=$SECONDS
  fi
  bash "$TESTS_DIR/$suite.sh" || FAILED+=("$suite")
  if [ -n "${DOTFILES_SUITE_TIMING_LOG:-}" ]; then
    printf '%s\t%d\n' "$suite" "$((SECONDS - started))" >>"$DOTFILES_SUITE_TIMING_LOG"
  fi
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "실패한 스위트: ${FAILED[*]}"
  exit 1
fi
echo "dotfiles 회귀 테스트 전체 통과"
