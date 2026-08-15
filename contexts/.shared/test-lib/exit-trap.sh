#!/usr/bin/env bash
# exit-trap.sh - EXIT 트랩을 호출자의 것을 파괴하지 않고 겹쳐 쓰기 위한 공용 헬퍼 (SSOT)
#
# [배경]
# `trap '<cmd>' EXIT` 는 기존 트랩에 추가하는 게 아니라 통째로 교체한다. 그래서
# 라이브러리 함수나 스크립트 중간의 함수가 자기 임시 디렉토리를 치우려고 무심코
# 트랩을 걸면, 그 시점까지 호출자가 걸어 둔 정리 로직이 조용히 사라진다. 실제로 이
# 저장소에도 같은 형태가 세 곳(aws/tests/run.sh 의 tf_run_checkov_pair,
# containers/tests/run.sh 의 run_trivy_misconfig_pair / run_hardening_gate_pair) 있었고,
# 전부 "함수 끝에서 rm -rf 를 직접 하니까 괜찮다"는 전제 위에 서 있었다. 그 전제는
# 호출 순서가 바뀌는 순간 깨진다 — 라이브러리 쪽 트랩이 나중에 걸리면 호출자의
# 임시 디렉토리가 스크립트가 끝나도 남는다.
#
# 그 checkov 러너의 예전 주석은 "`trap - EXIT` 로 해제하지 않는다(호출자 트랩이
# 날아가므로)"까지는 짚었지만, 정작 "거는 것 자체가 이미 호출자 트랩을 덮어썼다"는
# 점은 놓치고 있었다. 이 헬퍼는 그 절반을 마저 채운다.
#
# [한계] push 와 pop 사이에 인터럽트가 들어오면, 그 구간에서는 우리 트랩만 살아 있어
# 호출자가 걸어 둔 정리는 실행되지 않는다(트랩 본문을 이어붙이려면 `trap -p` 출력의
# 따옴표를 파싱해야 하는데, 본문에 따옴표가 섞이면 그 파싱이 먼저 깨진다). 정상 흐름과
# 스크립트 종료 시점의 정리는 완전히 보장되며, 남는 것은 인터럽트 순간의 임시 디렉토리
# 하나뿐이라 이 절충을 택했다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source ".../test-lib/exit-trap.sh"
#   tmpdir=$(mktemp -d)
#   push_exit_trap 'rm -rf "${tmpdir:-}"'
#   ...
#   rm -rf "$tmpdir"
#   pop_exit_trap

# push/pop 이 중첩될 수 있으므로 스택으로 관리한다.
_EXIT_TRAP_SAVED=()

# push_exit_trap <command>
# 현재 EXIT 트랩을 스택에 저장한 뒤 <command> 를 EXIT 트랩으로 건다.
push_exit_trap() {
  _EXIT_TRAP_SAVED+=("$(trap -p EXIT)")
  # 여기서는 홑따옴표가 아니라 겹따옴표가 맞다. $1 은 호출자가 넘긴 "트랩 본문 문자열"
  # 자체이므로 지금 전개돼 그 값이 트랩으로 등록돼야 한다. 홑따옴표로 두면 리터럴
  # '$1' 이 트랩 본문이 되어 아무것도 정리하지 못한다.
  # shellcheck disable=SC2064
  trap "$1" EXIT
}

# pop_exit_trap
# 짝이 되는 push_exit_trap 직전의 EXIT 트랩 상태로 정확히 되돌린다.
# 저장된 값이 비어 있으면(그 시점에 트랩이 없었으면) 우리 트랩만 걷어낸다.
pop_exit_trap() {
  local n=${#_EXIT_TRAP_SAVED[@]} prev
  [ "$n" -gt 0 ] || return 0

  prev="${_EXIT_TRAP_SAVED[$((n - 1))]}"
  # 슬라이스로 다시 만들어 항상 조밀하게 유지한다.
  # (예전 주석은 "unset 으로 지우면 배열이 성기어져 다음 pop 의 인덱스 계산이 어긋난다"고
  #  했지만 사실이 아니다 — pop 은 항상 마지막 요소만 제거하고, 마지막 요소를 unset 하면
  #  남는 인덱스는 0..n-2 로 조밀하며 ${#arr[@]} 도 정확하다. 실측상 두 방식의 결과가
  #  동일하다. 성기어지는 것은 중간 요소를 unset 할 때뿐이다. 그래도 슬라이스를 쓰는 이유는
  #  어느 위치를 제거하든 조밀함이 보장돼 의도가 코드에 그대로 드러나기 때문이다.)
  _EXIT_TRAP_SAVED=("${_EXIT_TRAP_SAVED[@]:0:$((n - 1))}")

  if [ -n "$prev" ]; then
    # `trap -p EXIT` 는 그대로 eval 하면 복원되는 형태(trap -- '<본문>' EXIT)로 출력된다.
    eval "$prev"
  else
    trap - EXIT
  fi
}
