#!/usr/bin/env bash
# 비교 불가·수동·주간 실행은 설치 검증을 유지한다.
set -euo pipefail

case "${EVENT_NAME:-}" in
pull_request)
  base=${BASE_SHA:-}
  head=${HEAD_SHA:-}
  mode="pr"
  ;;
push)
  base=${BEFORE_SHA:-}
  head=${AFTER_SHA:-}
  mode=push
  ;;
*)
  echo 'run=true'
  exit 0
  ;;
esac
if ! git cat-file -e "${base}^{commit}" 2>/dev/null ||
  ! git cat-file -e "${head}^{commit}" 2>/dev/null; then
  echo 'run=true'
  exit 0
fi
if [ "$mode" = pr ]; then
  base=$(git merge-base "$base" "$head") || {
    echo 'run=true'
    exit 0
  }
fi
changes=$(mktemp)
trap 'rm -f "$changes"' EXIT
if ! git diff --name-only --no-renames -z "$base" "$head" >"$changes"; then
  echo 'run=true'
  exit 0
fi
while IFS= read -r -d '' file; do
  case "$file" in
  bootstrap.sh | Justfile | ansible/* | stow/* | bin/* | .github/* | contexts/*/scripts/* | contexts/*/tests/* | contexts/*/SKILL.md | contexts/base.AGENTS.md)
    echo 'run=true'
    exit 0
    ;;
  esac
done <"$changes"
echo 'run=false'
