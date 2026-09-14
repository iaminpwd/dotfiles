#!/usr/bin/env bash
# Stop용 핵심 회귀 테스트 선택. 도메인 스위트와 전체 회귀 검증은 CI/명시적 실행에 남긴다.
set -euo pipefail
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

TESTS=()
declare -A SEEN=()
add_test() {
  local test=$1
  [ -z "${SEEN[$test]:-}" ] || return 0
  SEEN[$test]=1
  if [ -f "$ROOT/$test" ]; then
    TESTS+=("$ROOT/$test")
  else
    echo "[ERROR] 연결된 회귀 테스트가 없습니다: $test" >&2
    exit 1
  fi
}
dotfiles_test() { add_test "contexts/dotfiles/tests/test-$1.sh"; }
preflight_tests() {
  local name
  for name in quick-profile shell yaml; do
    add_test "contexts/pre-flight-check/tests/test-$name.sh"
  done
}

while IFS= read -r -d '' file; do
  case "$file" in
  contexts/dotfiles/tests/fixtures-ansible/*) dotfiles_test ansible ;;
  contexts/dotfiles/tests/fixtures-run-suite/*) dotfiles_test run-suite ;;
  contexts/pre-flight-check/tests/fixtures-shell/*) add_test contexts/pre-flight-check/tests/test-shell.sh ;;
  contexts/pre-flight-check/tests/fixtures-yaml/*) add_test contexts/pre-flight-check/tests/test-yaml.sh ;;
  */tests/fixtures*) continue ;;
  contexts/dotfiles/tests/test-*.sh | contexts/pre-flight-check/tests/test-*.sh)
    # 의도적으로 깨진 픽스처는 실행하지 않으며 삭제된 테스트는 등록 검사에서 확인한다.
    if [ -f "$file" ]; then add_test "$file"; fi
    ;;
  bin/hooks/pre-flight-check.sh | bin/lib/pfc-quality-checks.sh)
    preflight_tests
    ;;
  bin/lib/pfc-iac-checks.sh)
    preflight_tests
    dotfiles_test ansible
    ;;
  bin/hooks/stop-regression-check.sh) dotfiles_test stop-regression-check ;;
  bin/hooks/plugins/*) ;; # 도메인 정책은 명시적 실행 또는 CI에서 검증한다.
  bin/hooks/*.sh | bin/utils/*.sh | bin/lib/*.sh)
    name=${file##*/}
    name=${name%.sh}
    case "$name" in
    record-provenance) add_test contexts/prompt-architect/tests/test-record-provenance.sh ;;
    run-setup) dotfiles_test setup-behavior ;;
    tool-probe) dotfiles_test tool-probe-ssot ;;
    *)
      if [ -f "contexts/dotfiles/tests/test-$name.sh" ]; then
        dotfiles_test "$name"
      elif [ -e "$file" ]; then
        echo "[WARNING] Stop 회귀 매핑 없음: $file — 관련 스위트를 명시적으로 실행하십시오."
      fi
      ;;
    esac
    ;;
  bin/linters/prompt-lint.sh) add_test contexts/prompt-architect/tests/test_prompt_lint.sh ;;
  bin/linters/test-coverage-check.sh) dotfiles_test test-coverage-check ;;
  bootstrap.sh)
    dotfiles_test setup-behavior
    dotfiles_test bootstrap-changes
    dotfiles_test install-mise
    ;;
  ansible/roles/ai_agent/*)
    dotfiles_test agent-batch-backup
    dotfiles_test safe-link-backup
    dotfiles_test merge-agent-hooks
    dotfiles_test prune-orphan-skills
    dotfiles_test check-agent-collision
    ;;
  ansible/roles/stow/*) dotfiles_test stow-backup ;;
  ansible/roles/zsh/*) dotfiles_test zsh-updates ;;
  ansible/roles/tflint/*) dotfiles_test tflint-init ;;
  ansible/*) dotfiles_test setup-behavior ;;
  stow/git/.githooks/*) dotfiles_test "${file##*/}-hook" ;;
  stow/zsh/*) dotfiles_test zshrc-activation ;;
  stow/git/*) dotfiles_test setup-behavior ;;
  .github/scripts/*.sh)
    name=${file##*/}
    dotfiles_test "${name%.sh}"
    ;;
  .github/scripts/ci-tool-config.py | stow/mise/*) dotfiles_test ci-tool-config ;;
  esac
done < <(
  git diff --cached --name-only --no-renames -z
  git diff --name-only --no-renames -z
  git ls-files --others --exclude-standard -z
)

if [ "${1:-}" = --list ]; then
  [ "${#TESTS[@]}" -eq 0 ] || printf '%s\n' "${TESTS[@]}"
  exit 0
fi
[ "$#" -eq 0 ] || {
  echo "사용법: $0 [--list]" >&2
  exit 2
}
[ "${#TESTS[@]}" -gt 0 ] || exit 0
if ! PFC_PROFILE=full bash "$ROOT/bin/hooks/run-suite.sh" "${TESTS[@]}"; then
  echo "[ERROR] 변경 영역 회귀 테스트 실패. 개별 재현 명령:" >&2
  printf 'bash %q\n' "${TESTS[@]}" >&2
  exit 1
fi
