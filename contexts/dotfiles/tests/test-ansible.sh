#!/usr/bin/env bash
# test-ansible.sh
#
# validate_ansible(pre-flight-check.sh)는 이전까지 어떤 fixture 테스트도 없었다
# (2026-08-01 실측: 13개 validate_* 중 SAM/Bicep/Ansible/Helm/conftest/FinOps
# 6개가 커버리지 0%). 이 저장소의 실제 ansible 사용처(ansible/site.yml, bootstrap.sh)와
# 가장 밀접한 워크스페이스라 dotfiles에 둔다.
#
# ansible-playbook --syntax-check는 파일 인자를 직접 받지만, ansible-lint는 인자
# 없이 현재 디렉토리를 통째로 스캔한다(pre-flight-check.sh의 validate_ansible과
# 동일). 그래서 lint 케이스만 격리된 디렉토리(lint-ok/, lint-fail/)로 따로 두고
# cd 해서 실행한다 — 그러지 않으면 이 저장소의 실제 ansible/ 디렉토리까지 스캔
# 범위에 들어와 픽스처 테스트가 무관한 결과에 흔들린다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-ansible.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures-ansible"

PASS_COUNT=0
FAIL_COUNT=0

require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치: $1 — 'mise install $1' 후 다시 실행하십시오"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "=== ansible 검증 회귀 테스트 ==="

echo "--- ansible-playbook --syntax-check ---"
if require_tool ansible-playbook; then
  status=0
  ansible-playbook --syntax-check "$FIXTURES/ok-playbook.yml" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-playbook (유효한 문법)" 0; else report "ok-playbook (유효한 문법)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  ansible-playbook --syntax-check "$FIXTURES/fail-syntax-playbook.yml" >/dev/null 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then report "fail-syntax-playbook (문법 오류 차단)" 0; else report "fail-syntax-playbook (문법 오류 차단)" 1 "기대 exit≠0 / 실제 exit=$status"; fi
fi

echo "--- ansible-lint ---"
if require_tool ansible-lint; then
  status=0
  (cd "$FIXTURES/lint-ok" && ansible-lint >/dev/null 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then report "lint-ok (지적 0건)" 0; else report "lint-ok (지적 0건)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  out=$(cd "$FIXTURES/lint-fail" && ansible-lint 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "name[missing]" <<<"$out"; then
    report "lint-fail (name[missing] 규칙 위반 차단)" 0
  else
    report "lint-fail (name[missing] 규칙 위반 차단)" 1 "기대 exit≠0 + name[missing] 문구 / 실제 exit=$status"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
