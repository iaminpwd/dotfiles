#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <file_path> <rule_source> <purpose>"
  echo "Example: $0 src/main.py 050-rule-provenance-standard.md \"Refactor authentication\""
  exit 1
fi

FILE_PATH="$1"
RULE_SOURCE="$2"
PURPOSE="$3"
ISO8601=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TARGET_DIR=".agent-state"

mkdir -p "$TARGET_DIR"
# Format: <ISO8601> | <파일경로> | <출처> | <작업 목적> | <결과>
# idempotency:bypass (로그 파일 연속 기록이므로 상태 검증 불필요)
echo "$ISO8601 | $FILE_PATH | agent:$RULE_SOURCE | $PURPOSE | SUCCESS" >>"$TARGET_DIR/edits.log"
echo "✅ Logged edit to $TARGET_DIR/edits.log"
