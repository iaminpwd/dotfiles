#!/usr/bin/env bash
# multi-cloud Terraform 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 010-multi-cloud-core.md 의 특정 조항이나 중단 조건을 재현한다. 목적은
# pre-flight-check.sh 의 validate_terraform 을 손볼 때, 기존 검사가 조용히 죽어서
# 위반 IaC 코드가 통과되는 상황을 제어하는 것이다.
#
# multi-cloud 룰북은 AWS/Azure 코어 룰을 교차 참조하므로(§1 동적 지식 융합 가이드),
# 픽스처는 aws/azure 스킬과 동일한 검증 게이트(fmt/validate/tflint/checkov)를 그대로
# 통과해야 하되, 리소스 자체는 하이브리드 연동(VPN 터널) 시나리오로 구성했다.
#
# 러너 로직은 aws/azure/openstack 이 동일하므로 공용 라이브러리에 있다.
#
# 사용: bash ~/dotfiles/contexts/multi-cloud/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/tf-fixture-lib.sh"

echo "=== multi-cloud Terraform 검증 파이프라인 회귀 테스트 ==="
tf_run_standard_suite "$TESTS_DIR/fixtures" CKV_AWS_24
