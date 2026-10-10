#!/usr/bin/env bash
# Discover standalone regression scripts by filename, not a manually kept list.
# Used by dotfiles, pre-flight-check and prompt-architect domain runners.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != --list ]; }; then
  echo "usage: $0 TESTS_DIR [--list]" >&2
  exit 2
fi

TESTS_DIR=$(cd "$1" && pwd -P) || exit 1
shopt -s nullglob
# Keep both legacy naming forms; quote every path so spaces are supported.
TESTS=("$TESTS_DIR"/test-*.sh "$TESTS_DIR"/test_*.sh)
shopt -u nullglob

if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "[ERROR] 발견된 회귀 테스트가 없습니다: $TESTS_DIR" >&2
  exit 1
fi

if [ "${2:-}" = --list ]; then
  printf '%s\n' "${TESTS[@]}"
  exit 0
fi

FAILED=()
for suite in "${TESTS[@]}"; do
  name=${suite##*/}
  if [ -n "${DOTFILES_SUITE_TIMING_LOG:-}" ]; then
    started=$SECONDS
  fi
  # The runner executes each test with Bash regardless of executable bit.
  # Do not abort on the first failure: expose every broken case in one run.
  bash "$suite" || FAILED+=("$name")
  if [ -n "${DOTFILES_SUITE_TIMING_LOG:-}" ]; then
    printf '%s\t%d\n' "${name%.sh}" "$((SECONDS - started))" >>"$DOTFILES_SUITE_TIMING_LOG"
  fi
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '[ERROR] 실패한 회귀 테스트: %s\n' "${FAILED[*]}" >&2
  exit 1
fi
echo "회귀 테스트 전체 통과: $TESTS_DIR"
