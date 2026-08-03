#!/usr/bin/env bash
# idempotency-check.sh 재현: 파일 append 위아래 3줄 이내에 상태 확인 가드가 전혀
# 없으면 경고가 떠야 한다. 판정 윈도우 밖까지 벌리기 위해 앞뒤에 무관한 줄을
# 채워 넣는다. (주석에 검사 대상 리터럴 연산자를 쓰지 않는다 — 우발적 오탐/오가드
# 유발을 피하기 위함.)
set -euo pipefail

echo "unrelated line 1"
echo "unrelated line 2"
echo "unrelated line 3"
echo "unrelated line 4"
echo "unguarded append" >> /tmp/output.log
echo "unrelated line 5"
echo "unrelated line 6"
echo "unrelated line 7"
echo "unrelated line 8"
