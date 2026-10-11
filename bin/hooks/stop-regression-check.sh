#!/usr/bin/env bash
# Stop용 핵심 회귀 테스트 선택. 도메인 스위트와 전체 회귀 검증은 CI/명시적 실행에 남긴다.
# macOS의 /bin/bash 3.2에는 아래 declare -A가 없다. Stop/GUI처럼 제한된
# PATH에서 시작해도 선택기와 자식 테스트가 동일한 현대 Bash를 사용하게 한다.
if [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
  { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash "${HOME:-}/.local/share/mise/shims/bash"; do
    # shellcheck disable=SC2016
    if [ -x "$candidate" ] &&
      "$candidate" -c '[[ "${BASH_VERSINFO[0]}" -gt 4 || ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 ) ]]' >/dev/null 2>&1; then
      PATH="$(dirname "$candidate"):$PATH"
      export PATH
      exec "$candidate" "$0" "$@"
    fi
  done
  echo '[ERROR] Stop regression selector requires Bash 4.4+.' >&2
  exit 2
fi
set -euo pipefail

# GNU readlink -f는 macOS 기본 BSD readlink에 없다. 이 selector는 Stop hook에서 호출되므로
# Homebrew coreutils의 gnubin PATH를 전제로 하지 않고 plain readlink + cd -P로 자기
# symlink 체인을 해석한다.
canonical_path() {
  local path=$1 dir target
  while [ -L "$path" ]; do
    dir=$(cd -P "$(dirname "$path")" && pwd) || return 1
    target=$(readlink "$path") || return 1
    case "$target" in
    /*) path="$target" ;;
    *) path="$dir/$target" ;;
    esac
  done
  dir=$(cd -P "$(dirname "$path")" && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

SCRIPT_PATH=$(canonical_path "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
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
  tests/lib/parallel-pair.sh) add_test contexts/pre-flight-check/tests/test-parallel-pair.sh ;;
  tests/lib/exit-trap.sh) add_test contexts/pre-flight-check/tests/test-exit-trap.sh ;;
  tests/lib/run-domain-tests.sh)
    dotfiles_test run-suite
    dotfiles_test test-coverage-check
    ;;
  tests/lib/*.sh)
    [ ! -e "$file" ] || echo "[WARNING] Stop 회귀 매핑 없음: $file — 관련 스위트를 명시적으로 실행하십시오."
    ;;
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
  bin/utils/safe-link-backup.py) dotfiles_test safe-link-backup ;;
  bin/utils/stow-safe-backup.py) dotfiles_test stow-toctou ;;
  bin/utils/stow-safe-install.py)
    # Bootstrap, drift detection and Ansible Stow apply share this installer.
    for name in stow-drift-portability stow-ignore stow-package-conflicts stow-real-failure stow-toctou; do
      dotfiles_test "$name"
    done
    ;;
  bin/utils/stow-safe-role-init.py)
    dotfiles_test stow-legacy-mise-link
    dotfiles_test stow-toctou
    ;;
  bin/utils/stow-filter-inventory.pl)
    dotfiles_test stow-ignore
    dotfiles_test stow-drift-portability
    ;;
  bin/utils/*.py | bin/utils/*.pl)
    # Non-shell Stow helpers must not silently bypass Stop selection when added.
    [ ! -e "$file" ] || echo "[WARNING] Stop 회귀 매핑 없음: $file — 관련 스위트를 명시적으로 실행하십시오."
    ;;
  bin/hooks/plugins/*) ;; # 도메인 정책은 명시적 실행 또는 CI에서 검증한다.
  bin/hooks/*.sh | bin/utils/*.sh | bin/lib/*.sh)
    name=${file##*/}
    name=${name%.sh}
    case "$name" in
    record-provenance) add_test contexts/prompt-architect/tests/test-record-provenance.sh ;;
    run-setup) dotfiles_test setup-behavior ;;
    tool-probe) dotfiles_test tool-probe-ssot ;;
    broken-symlink-detector) dotfiles_test detector-logic ;;
    prune-orphan-agent-scripts) dotfiles_test agent-script-update-prune ;;
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
  bin/linters/idempotency-check.sh) add_test contexts/pre-flight-check/tests/test-idempotency.sh ;;
  bin/linters/db-sg-checker.sh) add_test contexts/pre-flight-check/tests/test-db-sg.sh ;;
  bin/linters/container-hardening-gate.sh) add_test contexts/containers/tests/run.sh ;;
  bin/linters/semantic-commit-lint.sh) dotfiles_test semantic-commit-lint ;;
  bin/linters/*.sh)
    [ ! -e "$file" ] || echo "[WARNING] Stop 회귀 매핑 없음: $file — 관련 스위트를 명시적으로 실행하십시오."
    ;;
  bootstrap.sh)
    dotfiles_test setup-behavior
    dotfiles_test bootstrap-changes
    dotfiles_test install-mise
    ;;
  ansible/roles/ai_agent/*)
    dotfiles_test agent-batch-backup
    dotfiles_test agent-root-rule-backup
    dotfiles_test agent-script-update-prune
    dotfiles_test safe-link-backup
    dotfiles_test merge-agent-hooks
    dotfiles_test prune-orphan-skills
    dotfiles_test verify-bootstrap-env
    ;;
  ansible/roles/stow/*)
    dotfiles_test stow-backup
    dotfiles_test stow-drift-portability
    dotfiles_test stow-legacy-mise-link
    dotfiles_test stow-package-conflicts
    ;;
  ansible/roles/zsh/*)
    dotfiles_test zsh-updates
    dotfiles_test zsh-path-probe
    dotfiles_test zsh-shell-failure
    dotfiles_test zsh-supply-chain
    ;;
  ansible/roles/tflint/*) dotfiles_test tflint-init ;;
  ansible/*) dotfiles_test setup-behavior ;;
  stow/git/.githooks/*) dotfiles_test "${file##*/}-hook" ;;
  stow/zsh/*)
    dotfiles_test zshrc-activation
    dotfiles_test zshenv-path
    ;;
  stow/git/*) dotfiles_test setup-behavior ;;
  .github/scripts/*.sh)
    name=${file##*/}
    case "$name" in
    secret-history-scan.sh) dotfiles_test ci-secret-history ;;
    assert-idempotent-ansible-recap.sh) dotfiles_test bootstrap-idempotency-gate ;;
    *) dotfiles_test "${name%.sh}" ;;
    esac
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
