#!/usr/bin/env bash
# aws Terraform 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 050-iac-standard.md 의 특정 조항이나 중단 조건을 재현한다. 목적은
# pre-flight-check.sh 의 validate_terraform 을 손볼 때, 기존 검사가 조용히 죽어서
# 위반 IaC 코드가 통과되는 상황을 제어하는 것이다.
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
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source-path=SCRIPTDIR 은 shellcheck 가 아래 상대 경로를 이 스크립트의 디렉토리 기준으로
# 찾게 한다. 예전에는 SC1091 을 disable 로 억제했는데, 그러면 경로가 오타나 파일 이동으로
# 깨져도 린트가 통과한다. pre-flight-check.sh 가 shellcheck 를 -x 로 호출하므로 이제
# 라이브러리를 실제로 따라가 존재 여부까지 검증한다.
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../pre-flight-check/tests/lib/tf-fixture-lib.sh"

echo "=== aws Terraform 검증 파이프라인 회귀 테스트 ==="
tf_run_standard_suite "$TESTS_DIR/fixtures" CKV_AWS_24

# validate_sam(pre-flight-check.sh)은 이전까지 어떤 fixture 테스트도 없었다
# (2026-08-01 실측: 13개 validate_* 중 SAM/Bicep/Ansible/Helm/conftest/FinOps
# 6개가 커버리지 0%). sam CLI는 --region 없이는 템플릿 정합성과 무관한
# "AWS Region was not found" 오류만 내므로 AWS_DEFAULT_REGION을 명시한다.
echo
echo "=== aws SAM 템플릿 검증 회귀 테스트 ==="
SAM_FIXTURES="$TESTS_DIR/fixtures-sam"
SAM_PASS=0
SAM_FAIL=0

sam_report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    SAM_PASS=$((SAM_PASS + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    SAM_FAIL=$((SAM_FAIL + 1))
  fi
}

if command -v sam >/dev/null 2>&1; then
  export SAM_CLI_TELEMETRY=0 AWS_DEFAULT_REGION=us-east-1
  status=0
  sam validate --template-file "$SAM_FIXTURES/ok-baseline.yaml" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then sam_report "ok-baseline (유효한 SAM 템플릿)" 0; else sam_report "ok-baseline (유효한 SAM 템플릿)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  out=$(sam validate --template-file "$SAM_FIXTURES/fail-yaml-syntax.yaml" 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "Failed to parse template" <<<"$out"; then
    sam_report "fail-yaml-syntax (문법 오류 차단)" 0
  else
    sam_report "fail-yaml-syntax (문법 오류 차단)" 1 "기대 exit≠0 + 파싱 오류 문구 / 실제 exit=$status"
  fi
else
  sam_report "sam CLI" 1 "도구 미설치 — 'mise install' 후 다시 실행하십시오"
fi

SAM_TOTAL=$((SAM_PASS + SAM_FAIL))
echo
echo "$SAM_PASS/$SAM_TOTAL 통과"
[ "$SAM_FAIL" -eq 0 ] || exit 1
