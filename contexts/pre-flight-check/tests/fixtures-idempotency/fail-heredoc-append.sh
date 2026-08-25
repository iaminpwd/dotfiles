#!/usr/bin/env bash
# idempotency-check.sh 재현: 히어독 시작과 append 리다이렉트가 "한 줄"에 같이 있는
# 형태. dotfiles 에서 설정이 재실행마다 증식하는 가장 전형적인 비멱등 패턴인데,
# 히어독 본문 스킵이 시작 줄까지 함께 삼키면 이 줄이 append 후보로 등록조차 되지
# 않아 조용히 면제된다(실측 재현). 가드가 없으므로 경고가 떠야 한다.
# (주석에 검사 대상 리터럴 연산자를 쓰지 않는다 — 우발적 오탐/오가드 유발을 피하기 위함.)
set -euo pipefail

echo "unrelated line 1"
echo "unrelated line 2"
echo "unrelated line 3"
echo "unrelated line 4"
cat >>/tmp/output.log <<'EOF'
export SAMPLE_VAR=1
EOF
echo "unrelated line 5"
echo "unrelated line 6"
echo "unrelated line 7"
echo "unrelated line 8"
