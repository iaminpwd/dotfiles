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

# 실제 bootstrap 동작·설치 결과에 영향을 주는 경로만 smoke 대상으로 본다.
# contexts/*/tests/* 는 원본 저장소에서만 실행되고 ai_agent 롤이 배포하지 않으므로 제외한다.
# SKILL.md/base.AGENTS.md 는 고정 경로를 symlink로 노출하므로 내용(M)만 바뀐 경우 링크 설치
# 결과는 동일하다. 다만 추가/삭제(A/D)는 배포 에셋 존재 여부가 달라지므로 아래에서 별도 감지한다.
while IFS= read -r -d '' file; do
  case "$file" in
  bootstrap.sh | .gitignore | Justfile | ansible/* | stow/* | bin/* | .github/* | contexts/*/scripts/*)
    echo 'run=true'
    exit 0
    ;;
  esac
done <"$changes"

# symlink 대상 문서의 내용 수정은 smoke를 다시 돌릴 이유가 없지만, 파일 추가/삭제는
# fresh install에서 생성해야 할 링크 집합 자체를 바꾼다.
if ! git diff --quiet --no-renames --diff-filter=AD "$base" "$head" --   ':(glob)contexts/*/SKILL.md' contexts/base.AGENTS.md; then
  echo 'run=true'
  exit 0
fi

echo 'run=false'
