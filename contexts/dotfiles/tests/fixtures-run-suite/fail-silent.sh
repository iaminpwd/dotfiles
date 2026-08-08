#!/usr/bin/env bash
# 2026-07-28 실측 회귀: 출력이 전부 compact-runner 의 무시 패턴(PASS / "N/N 통과" /
# 구분선)에만 걸리는 실패 스크립트. 예전 stdout 패턴 판정에서는 `-> [✓]` 로 표시됐다.
set -euo pipefail

echo "--- 2회차 실행 ---"
echo "  PASS  첫 항목"
echo "3/5 통과"
exit 1
