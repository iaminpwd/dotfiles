#!/usr/bin/env bash
# idempotency-check.sh 재현: 탐지 대상은 리다이렉트 형식만이 아니라 tee 의 append
# 옵션도 포함한다. 이 축을 검증하는 픽스처가 없어서, 탐지 정규식에서 tee 쪽을 통째로
# 지워도 회귀 테스트가 그대로 통과했다(뮤테이션으로 확인). 리다이렉트 픽스처와 같은
# 이유로 판정 윈도우 밖까지 앞뒤를 무관한 줄로 채운다.
# (주석에 검사 대상 리터럴 연산자를 쓰지 않는다 — 우발적 오가드를 피하기 위함.)
set -euo pipefail

echo "unrelated line 1"
echo "unrelated line 2"
echo "unrelated line 3"
echo "unrelated line 4"
echo "unguarded append" | tee -a /tmp/output.log
echo "unrelated line 5"
echo "unrelated line 6"
echo "unrelated line 7"
echo "unrelated line 8"
