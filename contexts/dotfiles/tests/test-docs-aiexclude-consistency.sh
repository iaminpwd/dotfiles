#!/usr/bin/env bash
# README의 디렉토리 구조 설명이 실제 저장소 트리와 일치하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
README="$ROOT/README.md"
PATH_IN_DOC='contexts/.base.aiexclude'
BASENAME_IN_DOC='.base.aiexclude'
FILE="$ROOT/$PATH_IN_DOC"

if grep -qF "$BASENAME_IN_DOC" "$README" && [ ! -e "$FILE" ]; then
  echo "FAIL: README가 존재하지 않는 $PATH_IN_DOC 를 활성 파일로 문서화하고 있습니다."
  exit 1
fi

echo 'PASS: README의 .base.aiexclude 문서가 실제 저장소 상태와 일치함'
