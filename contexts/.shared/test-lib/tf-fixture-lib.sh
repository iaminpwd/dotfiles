#!/usr/bin/env bash
# Terraform 픽스처 회귀 테스트 공용 라이브러리
#
# aws / azure / openstack / multi-cloud 네 스킬이 검증하는 대상은 전부 pre-flight-check.sh 의
# validate_terraform 하나이므로, 러너 로직을 각 스킬에 복제하지 않고 여기서
# 공유한다. 복제하면 같은 러너 버그(예: set -e + grep 무매치로 조용히 죽는 버그)를
# 스킬마다 따로 고쳐야 하는 상황을 피하기 위함이다.
#
#
# 이 파일은 검증기가 아니라 회귀 테스트 전용 라이브러리라 scripts/ 가 아닌
# contexts/.shared/test-lib/ 에 둔다. scripts/ 는 Ansible 셋업 과정이 에이전트에게 심볼릭
# 링크로 노출하는 디렉토리이므로(Ansible 셋업 과정의 글로벌 스킬 등록 루프), 테스트
# 헬퍼가 거기 있으면 런타임 배포 표면에 불필요하게 포함된다. 특정 스킬 산하에 두지
# 않는 이유는 aws/azure/openstack/multi-cloud/containers/
# dotfiles 등 여러 스킬이 공유하는 자산이라, 이름과 위치만 봐도 "공유 자산"임이 드러나야
# 하기 때문이다. 이름에 평문(`shared`) 대신 점(`.shared`)을 쓰는 이유는 `.archive`와
# 동일하게 bash glob(dotglob 없이는 숨김 디렉토리를 건너뜀)이 이 폴더를 스킬 스캔 대상에서
# 구조적으로 자동 제외하게 하기 위함이다 — 평문 이름을 쓰면 하드코딩 제외 목록에 수동으로
# 등록해야 하고, 그 목록은 소비자가 늘어날 때 조용히 낡을 수 있다(실제로 이 저장소의
# `git/.githooks/pre-push`에 그런 드리프트 버그가 있었다).
#
# [정정] 예전 주석은 여기에 `ansible.builtin.find`(hidden 기본 미탐색)도 같은 근거로
# 들고 있었는데, 실측해 보니 사실이 아니다 — `hidden: false` 는 basename 이 점으로
# 시작하는 "파일"만 거를 뿐 숨김 "디렉토리" 안으로는 그대로 recurse 한다(ansible-core
# 2.19.11 확인). 그 잘못된 전제 때문에 `ansible/roles/ai_agent/tasks/main.yml` 의
# ~/.local/bin 링크 태스크가 아무 제외 없이 방치돼, `contexts/.archive/` 의 스크립트가
# 실제로 사용자 PATH 에 올라와 있었다. 지금은 그 태스크가 명시적으로 제외한다.
# 즉 이 이름 규약의 자동 제외 효과는 셸 glob 경로에만 해당하며, ansible 쪽은 명시적
# 조건이 필요하다.
#
# 이 파일은 단독 실행용이 아니다.

# 호출자(aws/azure/openstack/multi-cloud tests/run.sh)의 TESTS_DIR이 아니라 이 파일
# 자신의 실제 위치 기준으로 parallel-pair.sh를 찾는다 (호출자마다 상대경로가 다름).
_TF_FIXTURE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$_TF_FIXTURE_LIB_DIR/parallel-pair.sh"
# EXIT 트랩을 호출자 것을 파괴하지 않고 겹쳐 쓰기 위한 SSOT (exit-trap.sh 헤더 참조).
# shellcheck source-path=SCRIPTDIR
source "$_TF_FIXTURE_LIB_DIR/exit-trap.sh"

PASS_COUNT=0
FAIL_COUNT=0

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
# mise shim 은 command -v 로 항상 발견되므로 실제 호출까지 해봐야 한다.
#
# $2 에 'skip-version-probe' 를 주면 --version 호출을 생략한다. Go 바이너리(terraform,
# tflint)는 이 확인이 빠르지만 checkov 는 파이썬 인터프리터 기동만으로 스위트 전체
# 시간의 상당 부분을 차지한다. 생략해도 검출력은 그대로다: 도구가 실행 미지원하면
# ok 픽스처는 exit≠0 으로, 위반 픽스처는 기대 체크 ID 부재로 각각 FAIL 이 되어
# "조용한 통과"가 구조적으로 불가능하다. 잃는 것은 진단 메시지뿐이므로, 그 대신
# tf_judge_checkov 가 실패 상세에 출력 마지막 줄을 실어 원인을 보존한다.
tf_require_tool() {
  local tool=$1 mode=${2:-probe-version}
  if command -v "$tool" >/dev/null 2>&1; then
    if [ "$mode" = "skip-version-probe" ] || "$tool" --version >/dev/null 2>&1; then
      return 0
    fi
  fi
  echo "  FAIL  도구 미설치 또는 현재 위치에서 실행 실패: $tool"
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
    tf_report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo '중단' || echo '통과') / 실제 exit=$status"
  fi
}

# validate_terraform 의 'terraform fmt -check' 와 같은 게이트를 픽스처 디렉토리 단위로
# 재현한다. 검증기 쪽은 대상 .tf 파일 목록을 직접 넘기는 반면 여기서는 픽스처 디렉토리를
# 통째로 주므로 -recursive 가 필요하다 — 판정 기준(포맷 불일치 시 exit≠0)은 동일하고
# 대상 지정 방식만 다르다는 것을 분명히 해 둔다(예전 주석은 검증기도 -recursive 를
# 쓰는 것처럼 읽혀 실제 호출과 어긋나 있었다).
tf_run_fmt() {
  local dir=$1 label=$2 want_fail=$3 status
  terraform fmt -check -recursive "$dir" >/dev/null 2>&1 && status=0 || status=$?
  tf_assert_gate "$label (terraform fmt)" "$want_fail" "$status"
}

# validate_terraform 의 'tflint' 게이트를 픽스처 디렉토리 단위로 재현한다. 검증기는
# 저장소 루트(CWD)에서 인자 없이 부르고 여기서는 --chdir 로 픽스처를 지목하는데, 이는
# 대상 지정 방식의 차이일 뿐 판정 기준은 같다(tf_run_fmt 주석과 동일한 사유).
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
# 아무것도 완화하지 않으며, 어떤 지적이든 커밋을 중단한다.
# 이 러너는 스크립트의 의도가 아니라 실제 동작을 기준으로 검증한다.
tf_judge_checkov() {
  local label=$1 want_fail=$2 want_id=$3 status=$4 outfile=$5
  if [ -n "$want_id" ] && ! grep -q "$want_id" "$outfile"; then
    tf_report "$label (checkov)" 1 "기대 체크 '$want_id' 가 지적되지 않았습니다 (exit=$status): $(tail -1 "$outfile")"
    return
  fi
  tf_assert_gate "$label (checkov)" "$want_fail" "$status"
}

# ok / 위반 두 픽스처를 동시에 스캔한다. checkov 는 인터프리터 기동 비용이 커서 순차
# 호출이 느린데, 두 프로세스가 서로 다른 픽스처 디렉토리만 읽고 각자의 출력 파일과
# 종료 코드만 쓰므로 공유 상태가 없어 병렬화해도 안전하다. 검사 대상·옵션·판정 기준은
# 순차 실행일 때와 동일하며, 판정과 출력도 wait 이후 고정된 순서로 수행해 결과 출력
# 순서까지 그대로 유지한다.
# 병렬 실행 자체(백그라운드 + wait 종료 코드 회수)는 parallel-pair.sh(SSOT)에 위임한다.
tf_run_checkov_pair() {
  local ok_dir=$1 fail_dir=$2 fail_label=$3 want_id=${4:-}
  local tmpdir ok_status fail_status
  tmpdir=$(mktemp -d)
  # 스캔 도중 인터럽트되어 아래 rm 이 실행되지 못하는 경우에 대비한다.
  # `trap ... EXIT` 를 직접 걸면 호출자가 이미 걸어 둔 EXIT 트랩을 통째로 교체해 버리므로
  # (aws/azure tests/run.sh 가 각자 SAM_TMPDIR/BICEP_TMPDIR 정리를 걸어 둔다),
  # 반드시 push/pop 으로 감싸 원래 트랩을 복원한다 (exit-trap.sh 헤더 참조).
  # 홑따옴표가 맞다: 트랩 본문은 지금이 아니라 발동 시점에 전개돼야 한다.
  # shellcheck disable=SC2016
  push_exit_trap 'rm -rf "${tmpdir:-}"'

  # shellcheck disable=SC2034 # parallel_pair_run 안에서 nameref로 간접 참조됨
  local -a CMD_OK=(checkov --directory "$ok_dir" --framework terraform --compact --quiet --soft-fail-on "LOW,MEDIUM")
  # shellcheck disable=SC2034
  local -a CMD_FAIL=(checkov --directory "$fail_dir" --framework terraform --compact --quiet --soft-fail-on "LOW,MEDIUM")
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$tmpdir/ok" "$tmpdir/fail"

  tf_judge_checkov ok-baseline 0 "" "$ok_status" "$tmpdir/ok"
  tf_judge_checkov "$fail_label" 1 "$want_id" "$fail_status" "$tmpdir/fail"

  rm -rf "$tmpdir"
  # 위 push_exit_trap 직전의 EXIT 트랩 상태로 정확히 되돌린다. `trap - EXIT` 로 그냥
  # 해제하면 호출자가 걸어 둔 트랩까지 함께 날아가므로 반드시 pop 을 쓴다.
  pop_exit_trap
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
