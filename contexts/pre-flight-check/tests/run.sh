#!/usr/bin/env bash
# pre-flight-check 스킬 회귀 테스트 진입점
#
# pre-flight-check.sh 자체의 IaC 검증 로직(SAM/Helm/conftest/Ansible 등)은
# 각 클라우드 스킬의 스위트(aws/k8s/dotfiles 등)가 픽스처로 덮고 있으므로
# 여기서는 특정 클라우드에 속하지 않는 범용 래퍼/공용 로직만 다룬다.
#
# git 훅에서 bin/ 변경을 감지해 회귀 테스트를 안내하려면 "무엇이 바뀌면 어느
# 서브스위트를 봐야 하는지"가 1:1로 추적 가능해야 한다. 그래서 bin/linters/*.sh 등
# 대상 스크립트 1개당 서브스위트 파일 1개로 나눴다. 각 서브스위트는 독립적으로도
# 실행 가능하다.
#
# 한 서브스위트가 실패해도 나머지를 계속 실행한다. 먼저 실패한 쪽만 보고 끝내면
# 나머지 서브스위트의 상태를 다음 실행까지 알 수 없다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=()
for suite in test-parallel-pair test-exit-trap test-plugin-loop test-finops test-db-sg test-idempotency test-shell test-yaml; do
  bash "$TESTS_DIR/$suite.sh" || FAILED+=("$suite")
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "실패한 서브스위트: ${FAILED[*]}"
  exit 1
fi
echo "pre-flight-check 회귀 테스트 전체 통과"
