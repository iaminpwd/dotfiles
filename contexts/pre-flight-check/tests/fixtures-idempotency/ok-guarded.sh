#!/usr/bin/env bash
# idempotency-check.sh 재현: 파일 append 직전 3줄 이내에 상태 확인 가드가 있으면
# 경고가 뜨지 않아야 한다. (주석에 검사 대상 리터럴 연산자를 쓰지 않는다 —
# db-sg-checker.sh 픽스처와 같은 이유로 우발적 오탐/오가드를 유발하기 때문이다.)
set -euo pipefail

LOGFILE=/tmp/example.log

if ! grep -q "already logged" "$LOGFILE" 2>/dev/null; then
  echo "already logged" >> "$LOGFILE"
fi
