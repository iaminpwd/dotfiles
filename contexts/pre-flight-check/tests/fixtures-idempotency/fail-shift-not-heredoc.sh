#!/usr/bin/env bash
set -euo pipefail

# 산술 좌시프트는 히어독 시작이 아니다. 히어독으로 오인하면 이 아래 전체가
# 본문 취급되어 조용히 무검사 처리된다.
b=2
x=$((1 << b))
echo "$x"

echo "real unguarded" >> /tmp/example.log
