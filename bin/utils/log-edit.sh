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
ISO8601=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
TARGET_DIR=".agent-state"
EDITS_LOG="$TARGET_DIR/edits.log"

mkdir -p "$TARGET_DIR"

# 로그 구분자(|) 오염 방지: agent-edits-hook.sh와 동일한 새니타이즈 규칙
clean() { printf '%s' "$1" | tr '\t\r\n|' '    ' | sed -e 's/^ *//' -e 's/ *$//'; }
RULE_SOURCE_CLEAN=$(clean "$RULE_SOURCE")
PURPOSE_CLEAN=$(clean "$PURPOSE")

# agent-edits-hook.sh(PostToolUse)가 계산하는 상대경로와 동일한 기준으로 정규화
resolved=$(readlink -f "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
resolved_dir=$(dirname "$resolved")
git_root=$(git -C "$resolved_dir" rev-parse --show-toplevel 2>/dev/null) || git_root=""
if [ -n "$git_root" ]; then
  if [ "$resolved" = "$git_root" ]; then REL="$(basename "$resolved")"; else REL="${resolved#"$git_root"/}"; fi
else
  REL="$FILE_PATH"
fi

# Format: <ISO8601> | <파일경로> | <출처> | <작업 목적> | <결과>
# idempotency:bypass (로그 파일 연속 기록이므로 상태 검증 불필요)
#
# 훅이 방금 남긴 더미(-) 라인이 있으면 새 줄을 추가하는 대신 그 자리에서 실제
# 출처/목적으로 보강(overwrite)한다. 없으면(훅 미기동 등) 기존처럼 append한다.
if [ -f "$EDITS_LOG" ] && awk -F' \\| ' -v r="$REL" '$2==r && $4=="-" {found=1} END{exit !found}' "$EDITS_LOG"; then
  TMP="$EDITS_LOG.tmp.$$"
  awk -F' \\| ' -v r="$REL" -v src="agent:$RULE_SOURCE_CLEAN" -v purpose="$PURPOSE_CLEAN" '
    $2==r && $4=="-" { target=NR; tf1=$1; tf2=$2 }
    { line[NR]=$0 }
    END {
      for (i=1;i<=NR;i++) {
        if (i==target) {
          printf "%s | %s | %s | %s | SUCCESS\n", tf1, tf2, src, purpose
        } else {
          print line[i]
        }
      }
    }' "$EDITS_LOG" >"$TMP" && mv "$TMP" "$EDITS_LOG"
  echo "✅ 훅 더미 라인을 보강했습니다: $EDITS_LOG"
else
  echo "$ISO8601 | $REL | agent:$RULE_SOURCE_CLEAN | $PURPOSE_CLEAN | SUCCESS" >>"$EDITS_LOG"
  echo "✅ Logged edit to $EDITS_LOG"
fi
