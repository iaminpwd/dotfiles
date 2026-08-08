#!/usr/bin/env bash
# test-parallel-pair.sh
#
# parallel-pair.sh는 checkov/sam/bicep/trivy/ansible-lint 다섯 곳이 공유하는 "두 명령을
# 백그라운드로 동시 실행하고 종료 코드를 정확히 회수" SSOT다. wait의 종료 코드 회수가
# 조금만 어긋나도(예: 첫 번째 wait가 두 번째 PID를 잘못 회수) 실패 픽스처가 통과로
# 둔갑할 수 있으므로, 실제 병행성(순차보다 빠름)과 종료 코드/출력 격리를 함께 고정한다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-parallel-pair.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/parallel-pair.sh"

PASS_COUNT=0
FAIL_COUNT=0

report() {
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "--- parallel-pair.sh 공용 라이브러리 (SSOT) ---"

# 1. 둘 다 성공하면 두 rc가 모두 0이어야 한다.
CMD1=(bash -c 'echo out1')
CMD2=(bash -c 'echo out2')
rc1=99
rc2=99
parallel_pair_run CMD1 CMD2 rc1 rc2 "$TMP/o1" "$TMP/o2"
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  report "둘 다 성공 -> rc1=0, rc2=0" 0
else
  report "둘 다 성공 -> rc1=0, rc2=0" 1 "rc1=$rc1 rc2=$rc2"
fi

# 2. 각 명령의 출력이 서로 섞이지 않고 자기 파일에만 정확히 담겨야 한다.
if [ "$(cat "$TMP/o1")" = "out1" ] && [ "$(cat "$TMP/o2")" = "out2" ]; then
  report "출력 파일 격리 (서로 안 섞임)" 0
else
  report "출력 파일 격리 (서로 안 섞임)" 1 "o1=$(cat "$TMP/o1") o2=$(cat "$TMP/o2")"
fi

# 3. 하나는 성공, 하나는 실패해도 각자의 종료 코드가 정확히 회수돼야 한다
#    (다른 쪽 성공 여부와 무관하게).
CMD1=(bash -c 'exit 0')
CMD2=(bash -c 'exit 7')
rc1=99
rc2=99
parallel_pair_run CMD1 CMD2 rc1 rc2 "$TMP/o3" "$TMP/o4"
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 7 ]; then
  report "성공/실패 혼합 -> 각자 정확한 rc 회수" 0
else
  report "성공/실패 혼합 -> 각자 정확한 rc 회수" 1 "기대 rc1=0,rc2=7 / 실제 rc1=$rc1,rc2=$rc2"
fi

# 4. 순서를 바꿔도(먼저 넘긴 게 실패) 정확히 회수돼야 한다 -> wait 호출 순서와
#    무관하게 PID별로 올바른 종료 코드가 매칭되는지 확인한다.
CMD1=(bash -c 'exit 3')
CMD2=(bash -c 'exit 0')
rc1=99
rc2=99
parallel_pair_run CMD1 CMD2 rc1 rc2 "$TMP/o5" "$TMP/o6"
if [ "$rc1" -eq 3 ] && [ "$rc2" -eq 0 ]; then
  report "실패/성공 혼합(순서 반대) -> 각자 정확한 rc 회수" 0
else
  report "실패/성공 혼합(순서 반대) -> 각자 정확한 rc 회수" 1 "기대 rc1=3,rc2=0 / 실제 rc1=$rc1,rc2=$rc2"
fi

# 5. 실제 병행성 증명: 1초짜리 명령 2개가 순차(약 2초)가 아니라 동시(약 1초)에
#    끝나야 한다. 느슨한 임계값(1.5초)으로 환경 노이즈를 흡수한다.
# shellcheck disable=SC2034 # parallel_pair_run 안에서 nameref로 간접 참조됨
CMD1=(sleep 1)
# shellcheck disable=SC2034
CMD2=(sleep 1)
rc1=99
rc2=99
t0=$(date +%s.%N)
parallel_pair_run CMD1 CMD2 rc1 rc2 "$TMP/o7" "$TMP/o8"
t1=$(date +%s.%N)
elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')
if awk -v e="$elapsed" 'BEGIN{exit !(e < 1.5)}'; then
  report "실제 병행 실행 (1초 x2가 ~1초 -> $elapsed 초)" 0
else
  report "실제 병행 실행 (1초 x2가 ~1초 -> $elapsed 초)" 1 "순차 실행처럼 ~2초가 걸렸습니다: $elapsed 초"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
