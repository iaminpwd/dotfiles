#!/usr/bin/env bash
# semantic-commit-lint.sh
# Atomic Commit Analyzer
set -euo pipefail

# args: list of staged files
STAGED_FILES=("$@")

if [ ${#STAGED_FILES[@]} -gt 4 ]; then
  TOPLEVELS=()
  for file in "${STAGED_FILES[@]}"; do
    top="${file%%/*}"
    if [ "$top" != "$file" ]; then
      TOPLEVELS+=("$top")
    else
      TOPLEVELS+=("ROOT")
    fi
  done

  UNIQUE_CONTEXTS=$(printf "%s\n" "${TOPLEVELS[@]:-}" | sort -u | grep -c -v "^$" || true)

  if [ "$UNIQUE_CONTEXTS" -gt 2 ]; then
    echo "⚠️ [WARNING] Atomic Commit 위반 가능성: ${#STAGED_FILES[@]}개의 파일이 $UNIQUE_CONTEXTS 개의 서로 다른 디렉토리(Context)에 걸쳐 수정되었습니다." >&2
    echo "    관련 없는 기능이 한 번에 커밋되는 것은 아닌지 확인하십시오. (예: aws와 zsh가 섞임)" >&2
  fi
fi

exit 0
