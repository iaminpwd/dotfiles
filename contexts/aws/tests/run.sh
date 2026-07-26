#!/usr/bin/env bash
# aws Terraform 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 050-iac-standard.md 의 특정 조항이나 중단 조건을 재현한다. 목적은
# pre-flight-check.sh 의 validate_terraform 을 손볼 때, 기존 검사가 조용히 죽어서
# 위반 IaC 코드가 통과되는 상황을 막는 것이다.
#
# Terraform 계열 도구는 파일이 아니라 디렉토리를 대상으로 동작하므로 픽스처도
# 디렉토리 단위다. ok-baseline 을 제외한 모든 픽스처는 게이트 하나씩만 건드린다.
#
# terraform validate 는 init 이 선행돼야 하는데, 벤더 프로바이더를 쓰면 init 이
# 레지스트리에서 바이너리를 받아야 해서 테스트가 네트워크에 의존하게 된다.
# 그래서 fail-validate 픽스처만 프로바이더 없는 config 로 따로 구성했다.
#
# 러너 로직은 aws/azure/openstack 이 동일하므로 공용 라이브러리에 있다.
#
# 사용: bash ~/dotfiles/contexts/aws/tests/run.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 공용 라이브러리는 실행 시점에 절대 경로로 해석된다. shellcheck 는 이 경로를
# 정적으로 따라갈 수 없어 SC1091 을 내는데, pre-flight-check.sh 가 shellcheck 를
# 플래그 없이 호출하므로 info 등급도 커밋 차단 사유가 된다. 그래서 명시 억제한다.
# shellcheck disable=SC1091
source "$TESTS_DIR/../../pre-flight-check/scripts/tf-fixture-lib.sh"

echo "=== aws Terraform 검증 파이프라인 회귀 테스트 ==="
tf_run_standard_suite "$TESTS_DIR/fixtures" CKV_AWS_24
