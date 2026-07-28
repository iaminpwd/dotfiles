#!/usr/bin/env bash
# Handoff Blueprint Linter

set -euo pipefail

# args: list of files to check
FILES=("$@")

if [ ${#FILES[@]} -eq 0 ]; then
  exit 0
fi

for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || continue

  FILENAME=$(basename "$FILE")
  if [[ "$FILENAME" != "Claude-to-Gemini.md" && "$FILENAME" != "Gemini-to-Claude.md" ]]; then
    continue
  fi

  echo "🔍 Handoff blueprint linting: $FILENAME"

  # 1. Check for <task-id>
  if ! grep -qE "<task-id>.*</task-id>" "$FILE"; then
    echo "❌ [ERROR] Handoff lint failed: <task-id> 태그가 누락되었습니다." >&2
    exit 1
  fi

  # 2. Check Role specific headers
  if [ "$FILENAME" = "Claude-to-Gemini.md" ]; then
    for header in "## 1. Goal" "## 2. Architecture & Rules" "## 3. Action Plan" "## 4. Verification"; do
      if ! grep -q "^${header}" "$FILE"; then
        echo "❌ [ERROR] Handoff lint failed: 필수 헤더 '${header}' 가 누락되었습니다." >&2
        exit 1
      fi
    done
  elif [ "$FILENAME" = "Gemini-to-Claude.md" ]; then
    for header in "## 1. Status" "## 2. Actions Taken" "## 3. Logs" "## 4. Blockers & Questions"; do
      if ! grep -q "^${header}" "$FILE"; then
        echo "❌ [ERROR] Handoff lint failed: 필수 헤더 '${header}' 가 누락되었습니다." >&2
        exit 1
      fi
    done
  fi

  echo "  -> [✓] Handoff blueprint validation passed."
done

exit 0
