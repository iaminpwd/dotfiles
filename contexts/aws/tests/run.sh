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
# 이 스위트가 실제로 지키는 것은 "tflint/checkov 가 우리가 의존하는 룰 ID 를 여전히 낸다"는
# 도구 의존 계약이다(우리 코드는 경유하지 않는다 — validate_terraform 을 통째로 무력화해도
# 이 스위트는 통과한다. 그 축은 pre-flight-check/tests/test-plugin-loop.sh 의 배선 검사와
# 검증기 호출 스모크가 담당한다). Renovate 가 mise 도구 버전을 매주 자동으로 올리므로
# 그 계약은 실제로 흔들린다.
#
# 아래 tf_* 러너는 예전에 aws/azure/openstack/multi-cloud 네 스킬이 공유하던
# .shared/test-lib/tf-fixture-lib.sh 였다. 뒤의 셋을 지워 소비자가 이 파일 하나만 남은
# 뒤로는 공유 파일로 둘 이유가 없어 여기로 인라인했다(그 파일 자신이 남긴 지침이다).
# 벤더 스킬을 다시 살린다면 복제하지 말고 그때 다시 .shared 로 빼낼 것.
#
# 사용: bash ~/dotfiles/contexts/aws/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source-path=SCRIPTDIR 은 shellcheck 가 아래 상대 경로를 이 스크립트의 디렉토리 기준으로
# 찾게 한다. pre-flight-check.sh 가 shellcheck 를 -x 로 호출하므로, 이 설정 덕에 경로 오타나
# 파일 이동으로 인한 깨짐까지 실제로 검증된다.
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/parallel-pair.sh"
# EXIT 트랩을 호출자 것을 파괴하지 않고 겹쳐 쓰기 위한 SSOT (exit-trap.sh 헤더 참조).
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/exit-trap.sh"

PASS_COUNT=0
FAIL_COUNT=0

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
# mise shim 은 command -v 로 항상 발견되므로 실제 호출까지 해봐야 한다.
#
# $2 에 'skip-version-probe' 를 주면 --version 호출을 생략한다. Go 바이너리(tflint)는
# 이 확인이 빠르지만 checkov 는 파이썬 인터프리터 기동만으로 스위트 전체 시간의 상당
# 부분을 차지한다. 생략해도 검출력은 그대로다: 도구가 실행 미지원하면 ok 픽스처는
# exit≠0 으로, 위반 픽스처는 기대 체크 ID 부재로 각각 FAIL 이 되어 "조용한 통과"가
# 구조적으로 불가능하다. 잃는 것은 진단 메시지뿐이므로, 그 대신 tf_judge_checkov 가
# 실패 상세에 출력 마지막 줄을 실어 원인을 보존한다.
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
# 종료 코드는 도구마다 다르므로(tflint=2, checkov=1) 특정 값이 아니라 0 이 아님만 본다.
tf_assert_gate() {
  local name=$1 want_fail=$2 status=$3
  if [ "$want_fail" -eq "$([ "$status" -ne 0 ] && echo 1 || echo 0)" ]; then
    tf_report "$name" 0
  else
    tf_report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo '중단' || echo '통과') / 실제 exit=$status"
  fi
}

# validate_terraform 의 'tflint' 게이트를 픽스처 디렉토리 단위로 재현한다. 검증기는
# 저장소 루트(CWD)에서 인자 없이 부르고 여기서는 --chdir 로 픽스처를 지목하는데, 이는
# 대상 지정 방식의 차이일 뿐 판정 기준은 같다.
# want_rule 이 주어지면 그 룰이 실제로 지적됐는지까지 확인한다. 종료 코드만
# 보면 다른 룰이 대신 걸려도 통과로 오판할 수 있다.
tf_run_tflint() {
  local dir=$1 label=$2 want_fail=$3 want_rule=${4:-}
  local out status
  out=$(tflint --chdir="$dir" 2>&1) && status=0 || status=$?
  # `echo "$out" | grep -q` 를 쓰지 않는다. grep 이 첫 매치에서 stdin 을 닫으면 echo 가
  # SIGPIPE 로 141 을 반환하고, set -o pipefail 이 그것을 파이프라인 결과로 채택해
  # "룰을 찾았는데 못 찾음"으로 뒤집힌다. 현재 tflint 출력은 최대 327바이트라 파이프
  # 버퍼(64KB) 안에 들어가 발현되지 않지만, 출력이 커지는 순간 조용히 오탐이 된다.
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
  # `trap ... EXIT` 를 직접 걸면 아래 SAM 스위트가 걸어 둔 SAM_TMPDIR 정리 트랩을 통째로
  # 교체해 버리므로, 반드시 push/pop 으로 감싸 원래 트랩을 복원한다 (exit-trap.sh 헤더 참조).
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
  # 해제하면 SAM 스위트가 걸어 둔 트랩까지 함께 날아가므로 반드시 pop 을 쓴다.
  pop_exit_trap
}

echo "=== aws Terraform 검증 파이프라인 회귀 테스트 ==="
FIXTURES="$TESTS_DIR/fixtures"

echo "--- tflint ---"
if tf_require_tool tflint; then
  tf_run_tflint "$FIXTURES/ok-baseline" ok-baseline 0
  tf_run_tflint "$FIXTURES/fail-unpinned-version" fail-unpinned-version 1 terraform_required_version
fi

echo "--- checkov ---"
if tf_require_tool checkov skip-version-probe; then
  tf_run_checkov_pair "$FIXTURES/ok-baseline" "$FIXTURES/fail-open-ssh" fail-open-ssh CKV_AWS_24
fi

TF_TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TF_TOTAL 통과"

# sam CLI는 --region 없이는 템플릿 정합성과 무관한 "AWS Region was not found" 오류만
# 내므로 AWS_DEFAULT_REGION을 명시한다.
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

  # sam validate 는 Python 인터프리터 기동 비용이 커서 parallel-pair.sh(SSOT)로 서로
  # 무관한 두 픽스처를 동시에 돌린다.
  SAM_TMPDIR=$(mktemp -d)
  trap 'rm -rf "${SAM_TMPDIR:-}"' EXIT

  # shellcheck disable=SC2034 # parallel_pair_run 안에서 nameref로 간접 참조됨
  CMD_OK=(sam validate --template-file "$SAM_FIXTURES/ok-baseline.yaml")
  # shellcheck disable=SC2034
  CMD_FAIL=(sam validate --template-file "$SAM_FIXTURES/fail-yaml-syntax.yaml")
  ok_status=0
  fail_status=0
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$SAM_TMPDIR/ok" "$SAM_TMPDIR/fail"

  if [ "$ok_status" -eq 0 ]; then sam_report "ok-baseline (유효한 SAM 템플릿)" 0; else sam_report "ok-baseline (유효한 SAM 템플릿)" 1 "기대 exit=0 / 실제 exit=$ok_status"; fi

  if [ "$fail_status" -ne 0 ] && grep -qF "Failed to parse template" "$SAM_TMPDIR/fail"; then
    sam_report "fail-yaml-syntax (문법 오류 차단)" 0
  else
    sam_report "fail-yaml-syntax (문법 오류 차단)" 1 "기대 exit≠0 + 파싱 오류 문구 / 실제 exit=$fail_status"
  fi

  rm -rf "$SAM_TMPDIR"
else
  sam_report "sam CLI" 1 "도구 미설치 — 'mise install' 후 다시 실행하십시오"
fi

SAM_TOTAL=$((SAM_PASS + SAM_FAIL))
echo
echo "$SAM_PASS/$SAM_TOTAL 통과"
# Terraform 스위트 결과도 함께 판정한다. SAM 결과만 보면 위에서 실패한 Terraform 회귀가
# 종료 코드에 반영되지 않아 조용히 통과한다.
if [ "$SAM_FAIL" -ne 0 ] || [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
