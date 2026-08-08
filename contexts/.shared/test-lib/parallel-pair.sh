#!/usr/bin/env bash
# parallel-pair.sh - 서로 무관한 두 명령을 백그라운드로 동시에 실행하고 각각의
# 종료 코드를 정확히 회수하는 회귀 테스트 전용 공용 라이브러리.
#
# checkov(tf-fixture-lib.sh), sam validate(aws), bicep build(azure), trivy(containers),
# ansible-lint(dotfiles) 다섯 곳이 "인터프리터 기동 비용이 큰 CLI를 ok/fail 픽스처
# 두 개에 대해 순차 호출"하는 동일한 모양이라, 같은 백그라운드+wait 코드를 반복하지
# 않도록 이 라이브러리로 뽑아냈다.
#
# 판정 로직(무엇을 grep해서 pass/fail을 가릴지)은 도구마다 완전히 다르므로 여기서
# 다루지 않는다. 이 라이브러리는 "두 명령을 동시에 돌리고 결과 파일 + 종료 코드를
# 정확히 돌려준다"는 것만 책임지고, 판정은 호출자가 한다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source ".../lib/parallel-pair.sh"
#   local -a CMD1=(sam validate --template-file "$f1")
#   local -a CMD2=(sam validate --template-file "$f2")
#   local rc1 rc2
#   parallel_pair_run CMD1 CMD2 rc1 rc2 "$out1" "$out2"
#   # $out1/$out2 에 각 명령의 stdout+stderr, rc1/rc2 에 각 종료 코드가 담긴다.

# parallel_pair_run <cmd1_array_name> <cmd2_array_name> <rc1_var_name> <rc2_var_name> <out1> <out2>
parallel_pair_run() {
  local -n _ppr_cmd1=$1
  local -n _ppr_cmd2=$2
  local -n _ppr_rc1=$3
  local -n _ppr_rc2=$4
  local out1=$5 out2=$6

  "${_ppr_cmd1[@]}" >"$out1" 2>&1 &
  local pid1=$!
  "${_ppr_cmd2[@]}" >"$out2" 2>&1 &
  local pid2=$!

  # 위반 픽스처는 반드시 0이 아닌 코드로 끝나므로, set -e가 그 실패를 잡아 호출자를
  # 죽이지 않도록 wait의 종료 코드를 && / || 로 회수한다(tf_run_checkov_pair와 동일 이유).
  wait "$pid1" && _ppr_rc1=0 || _ppr_rc1=$?
  wait "$pid2" && _ppr_rc2=0 || _ppr_rc2=$?
}
