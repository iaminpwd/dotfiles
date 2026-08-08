#!/usr/bin/env bash
# 통과했지만 경고를 남기는 픽스처. 경고까지 접히면 "도구 미설치로 검증을 건너뛰었다"는
# pre-flight-check.sh 의 신호가 래퍼 단계에서 사라져 가짜 초록불이 된다.
set -euo pipefail

echo "  PASS  첫 항목"
echo "[WARNING] FIXTURE_SKIPPED_TOOL is not installed. Skipping."
echo "1/1 통과"
