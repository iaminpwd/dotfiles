#!/usr/bin/env bash
# Terraform 픽스처 회귀 테스트 공용 라이브러리
#
# aws / azure / openstack 세 스킬이 검증하는 대상은 전부 pre-flight-check.sh 의
# validate_terraform 하나이므로, 러너 로직을 각 스킬에 복제하지 않고 여기서
# 공유한다. 실제로 복제했다가 러너 버그를 세 번 고치는 상황을 피하기 위함이다
# (2026-07-26: containers 러너에서 set -e + grep 무매치로 조용히 죽는 버그를
# 겪은 뒤 이 구조로 결정).
#
#
# 이 파일은 검증기가 아니라 회귀 테스트 전용 라이브러리라 scripts/ 가 아닌 tests/lib/
# 에 둔다. scripts/ 는 setup.sh 가 에이전트에게 심볼릭 링크로 노출하는 디렉토리이므로
# (setup.sh 의 글로벌 스킬 등록 루프), 테스트 헬퍼가 거기 있으면 런타임 배포 표면에
# 불필요하게 포함된다. 또한 pre-commit 훅은 contexts/pre-flight-check/scripts/* 변경을
# "모든 스킬의 회귀 테스트 실행" 신호로 쓰는데, 이 파일을 쓰는 것은 tf 계열 3개 스킬
# 뿐이라 그 자리에 있으면 매번 과잉 실행됐다.
#
# 이 파일은 단독 실행용이 아니다.

PASS_COUNT=0
FAIL_COUNT=0

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
# mise shim 은 command -v 로 항상 발견되므로 실제 호출까지 해봐야 한다.
#
# $2 에 'skip-version-probe' 를 주면 --version 호출을 생략한다. Go 바이너리(terraform,
# tflint)는 이 확인이 0.03 초지만 checkov 는 파이썬 인터프리터 기동만으로 1.37 초가 들어
# 스위트 전체 시간의 18% 를 차지했다(2026-07-28 실측). 생략해도 검출력은 그대로다:
# 도구가 실행 불가능하면 ok 픽스처는 exit≠0 으로, 위반 픽스처는 기대 체크 ID 부재로
# 각각 FAIL 이 되어 "조용한 통과"가 구조적으로 불가능하다(exit 127 을 내는 가짜 checkov
# 로 두 케이스 모두 FAIL 임을 실측 확인). 잃는 것은 진단 메시지뿐이므로, 그 대신
# tf_judge_checkov 가 실패 상세에 출력 마지막 줄을 실어 원인을 보존한다.
tf_require_tool() {
  local tool=$1 mode=${2:-probe-version}
  if command -v "$tool" >/dev/null 2>&1; then
    if [ "$mode" = "skip-version-probe" ] || "$tool" --version >/dev/null 2>&1; then
      return 0
    fi
  fi
  echo "  FAIL  도구 미설치 또는 현재 위치에서 실행 불가: $tool"
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
  # `echo "$out" | grep -q` 를 쓰지 않는다. grep 이 첫 매치에서 stdin 을 닫으면 echo 가
  # SIGPIPE 로 141 을 반환하고, 호출자 스위트의 set -o pipefail 이 그것을 파이프라인
  # 결과로 채택해 "룰을 찾았는데 못 찾음"으로 뒤집힌다. 현재 tflint 출력은 최대 327바이트라
  # 파이프 버퍼(64KB) 안에 들어가 발현되지 않지만, 출력이 커지는 순간 조용히 오탐이 된다.
  # here-string 은 쓰는 쪽 프로세스가 없어 이 함정 자체가 성립하지 않는다.
  # (아래 checkov 검사가 outfile 을 직접 grep 하는 것과 같은 이유다.)
  if [ -n "$want_rule" ] && ! grep -q "$want_rule" <<<"$out"; then
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
#
# 실행부와 판정부를 나눈 이유는 tf_run_checkov_pair 의 병렬 호출에서 판정 로직을
# 그대로 재사용하기 위함이다. 판정 기준은 분리 전과 동일하다.
tf_exec_checkov() {
  local dir=$1 outfile=$2
  checkov --directory "$dir" --framework terraform --compact --quiet \
    --soft-fail-on LOW,MEDIUM >"$outfile" 2>&1
}

tf_judge_checkov() {
  local label=$1 want_fail=$2 want_id=$3 status=$4 outfile=$5
  if [ -n "$want_id" ] && ! grep -q "$want_id" "$outfile"; then
    tf_report "$label (checkov)" 1 "기대 체크 '$want_id' 가 지적되지 않았습니다 (exit=$status): $(tail -1 "$outfile")"
    return
  fi
  tf_assert_gate "$label (checkov)" "$want_fail" "$status"
}

# ok / 위반 두 픽스처를 동시에 스캔한다. checkov 는 인터프리터 기동에만 약 3 초가 들어
# 순차 호출이 6.1 초를 쓰는데, 두 프로세스가 서로 다른 픽스처 디렉토리만 읽고 각자의
# 출력 파일과 종료 코드만 쓰므로 공유 상태가 없어 3.25 초로 줄어든다(2026-07-28 실측,
# 5 코어). 검사 대상·옵션·판정 기준은 순차 실행일 때와 동일하며, 판정과 출력도 wait
# 이후 고정된 순서로 수행해 결과 출력 순서까지 그대로 유지한다.
tf_run_checkov_pair() {
  local ok_dir=$1 fail_dir=$2 fail_label=$3 want_id=${4:-}
  local tmpdir ok_pid fail_pid ok_status fail_status
  tmpdir=$(mktemp -d)
  # 스캔 도중 인터럽트되어 아래 rm 이 실행되지 못하는 경우에 대비한다.
  # 함수 반환 후 스크립트 종료 시점에 발동할 수 있으므로 set -u 하에서도 안전하도록
  # ${tmpdir:-} 로 참조한다(pre-flight-check.sh 의 infracost 임시파일과 동일한 처리).
  trap 'rm -rf "${tmpdir:-}"' EXIT

  tf_exec_checkov "$ok_dir" "$tmpdir/ok" &
  ok_pid=$!
  tf_exec_checkov "$fail_dir" "$tmpdir/fail" &
  fail_pid=$!

  # 위반 픽스처는 반드시 0 이 아닌 코드로 끝나므로, set -e 가 그 실패를 잡아 러너를
  # 죽이지 않도록 wait 의 종료 코드를 && / || 로 회수한다.
  wait "$ok_pid" && ok_status=0 || ok_status=$?
  wait "$fail_pid" && fail_status=0 || fail_status=$?

  tf_judge_checkov ok-baseline 0 "" "$ok_status" "$tmpdir/ok"
  tf_judge_checkov "$fail_label" 1 "$want_id" "$fail_status" "$tmpdir/fail"

  # `trap - EXIT` 로 해제하지 않는다. 라이브러리 함수가 트랩을 무조건 해제하면 호출자가
  # 걸어 둔 EXIT 트랩까지 함께 날아간다(setup.sh 에서 실제로 그 형태의 잔재가 임시 디렉토리
  # 정리를 무력화했다). 아래 rm 으로 이미 지운 뒤라 트랩이 다시 돌아도 무해하고, local
  # 변수라 함수 반환 후에는 ${tmpdir:-} 가 빈 문자열로 평가된다.
  rm -rf "$tmpdir"
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
  if tf_require_tool checkov skip-version-probe; then
    tf_run_checkov_pair "$fx/ok-baseline" "$fx/fail-open-ssh" fail-open-ssh "$ssh_check_id"
  fi

  local total=$((PASS_COUNT + FAIL_COUNT))
  echo
  echo "$PASS_COUNT/$total 통과"
  [ "$FAIL_COUNT" -eq 0 ]
}
