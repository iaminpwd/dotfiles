#!/usr/bin/env bash
# 실패 시 원형 로그가 압축되지 않고 그대로 보존되는지 확인하기 위한 픽스처.
set -euo pipefail

echo "  PASS  첫 항목"
echo "FIXTURE_RAW_DETAIL 진단에 필요한 원형 로그 한 줄"
exit 1
