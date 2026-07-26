#!/usr/bin/env bash
# Terraform 픽스처 회귀 테스트 공용 라이브러리
#
# aws / azure / openstack 세 스킬이 검증하는 대상은 전부 pre-flight-check.sh 의
# validate_terraform 하나이므로, 러너 로직을 각 스킬에 복제하지 않고 여기서
# 공유한다. 실제로 복제했다가 러너 버그를 세 번 고치는 상황을 피하기 위함이다
# (2026-07-26: containers 러너에서 set -e + grep 무매치로 조용히 죽는 버그를
# 겪은 뒤 이 구조로 결정).
#
# 사용법: 각 스킬의 tests/run.sh 에서 source 한 뒤 tf_run_standard_suite 호출.
#
# 이 파일은 단독 실행용이 아니다.

PASS_COUNT=0
FAIL_COUNT=0

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
# mise shim 은 command -v 로 항상 발견되므로 실제 호출까지 해봐야 한다.
tf_require_tool() {
  command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치 또는 현재 위치에서 실행 불가: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

tf_report() {
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

# want_fail=1 이면 게이트가 반드시 비정상 종료해야 한다.
# 종료 코드는 도구마다 다르므로(terraform fmt=3, tflint=2, checkov=1)
# 특정 값이 아니라 0 이 아님만 본다.
tf_assert_gate() {
  local name=$1 want_fail=$2 status=$3
  if [ "$want_fail" -eq "$([ "$status" -ne 0 ] && echo 1 || echo 0)" ]; then
    tf_report "$name" 0
  else
    tf_report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo '차단' || echo '통과') / 실제 exit=$status"
  fi
}

# validate_terraform 과 동일하게 'terraform fmt -check -recursive' 를 호출한다.
tf_run_fmt() {
  local dir=$1 label=$2 want_fail=$3 status
  terraform fmt -check -recursive "$dir" >/dev/null 2>&1 && status=0 || status=$?
  tf_assert_gate "$label (terraform fmt)" "$want_fail" "$status"
}

# validate_terraform 과 동일하게 'tflint' 를 호출한다.
# want_rule 이 주어지면 그 룰이 실제로 지적됐는지까지 확인한다. 종료 코드만
# 보면 다른 룰이 대신 걸려도 통과로 오판할 수 있다.
tf_run_tflint() {
  local dir=$1 label=$2 want_fail=$3 want_rule=${4:-}
  local out status
  out=$(tflint --chdir="$dir" 2>&1) && status=0 || status=$?
  if [ -n "$want_rule" ] && ! echo "$out" | grep -q "$want_rule"; then
    tf_report "$label (tflint)" 1 "기대 룰 '$want_rule' 이 지적되지 않았습니다 (exit=$status)"
    return
  fi
  tf_assert_gate "$label (tflint)" "$want_fail" "$status"
}

# validate_terraform 과 동일한 옵션으로 checkov 를 호출한다.
#
# 주의: OSS checkov 는 심각도(severity) 데이터를 제공하지 않아 모든 failed_check
# 의 severity 가 None 이다. 따라서 --soft-fail-on LOW,MEDIUM 은 실질적으로
# 아무것도 완화하지 못하며, 어떤 지적이든 커밋을 차단한다(2026-07-26 실측).
# 이 러너는 스크립트의 의도가 아니라 실제 동작을 기준으로 검증한다.
tf_run_checkov() {
  local dir=$1 label=$2 want_fail=$3 want_id=${4:-}
  local out status
  out=$(checkov --directory "$dir" --framework terraform --compact --quiet \
    --soft-fail-on LOW,MEDIUM 2>&1) && status=0 || status=$?
  if [ -n "$want_id" ] && ! echo "$out" | grep -q "$want_id"; then
    tf_report "$label (checkov)" 1 "기대 체크 '$want_id' 가 지적되지 않았습니다 (exit=$status)"
    return
  fi
  tf_assert_gate "$label (checkov)" "$want_fail" "$status"
}

# validate_terraform 과 동일하게 'terraform init -backend=false' 후 validate.
# init 산출물이 픽스처 디렉토리에 남으므로 성공·실패 어느 경로에서도 정리한다.
tf_run_validate() {
  local dir=$1 label=$2 want_fail=$3 status
  rm -rf "$dir/.terraform" "$dir/.terraform.lock.hcl"
  if ! terraform -chdir="$dir" init -backend=false -input=false >/dev/null 2>&1; then
    tf_report "$label (terraform validate)" 1 "terraform init 에 실패했습니다"
    rm -rf "$dir/.terraform" "$dir/.terraform.lock.hcl"
    return
  fi
  terraform -chdir="$dir" validate >/dev/null 2>&1 && status=0 || status=$?
  rm -rf "$dir/.terraform" "$dir/.terraform.lock.hcl"
  tf_assert_gate "$label (terraform validate)" "$want_fail" "$status"
}

# 세 스킬이 공유하는 표준 픽스처 구성을 한 번에 검증한다.
#   $1 fixtures 디렉토리
#   $2 fail-open-ssh 에서 기대하는 checkov 체크 ID (벤더마다 다름)
tf_run_standard_suite() {
  local fx=$1 ssh_check_id=$2

  echo "--- terraform fmt ---"
  if tf_require_tool terraform; then
    tf_run_fmt "$fx/ok-baseline" ok-baseline 0
    tf_run_fmt "$fx/fail-fmt" fail-fmt 1

    echo "--- terraform validate ---"
    tf_run_validate "$fx/fail-validate" fail-validate 1
  fi

  echo "--- tflint ---"
  if tf_require_tool tflint; then
    tf_run_tflint "$fx/ok-baseline" ok-baseline 0
    tf_run_tflint "$fx/fail-unpinned-version" fail-unpinned-version 1 terraform_required_version
  fi

  echo "--- checkov ---"
  if tf_require_tool checkov; then
    tf_run_checkov "$fx/ok-baseline" ok-baseline 0
    tf_run_checkov "$fx/fail-open-ssh" fail-open-ssh 1 "$ssh_check_id"
  fi

  local total=$((PASS_COUNT + FAIL_COUNT))
  echo
  echo "$PASS_COUNT/$total 통과"
  [ "$FAIL_COUNT" -eq 0 ]
}
