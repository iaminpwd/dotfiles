#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="$ROOT/.github/scripts/bootstrap-changes.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q
git config user.name Test
git config user.email test@example.com
mkdir -p ansible contexts/aws/references
printf 'base\n' >README.md
git add .
git -c core.hooksPath=/dev/null commit -qm 'chore: 초기 상태'
base=$(git rev-parse HEAD)
check() {
  local expected=$1
  shift
  actual=$(env "$@" bash "$SCRIPT")
  [ "$actual" = "run=$expected" ] || {
    echo "FAIL: $* => $actual"
    exit 1
  }
  echo "PASS: $*"
}
printf 'docs\n' >contexts/aws/references/010-core.md
git add .
git -c core.hooksPath=/dev/null commit -qm 'docs: 설명'
docs=$(git rev-parse HEAD)
check false EVENT_NAME=push BEFORE_SHA="$base" AFTER_SHA="$docs"
check false EVENT_NAME=pull_request BASE_SHA="$base" HEAD_SHA="$docs"
printf 'setup\n' >ansible/setup.yml
git add .
git -c core.hooksPath=/dev/null commit -qm 'feat: 설치'
setup=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$docs" AFTER_SHA="$setup"
check true EVENT_NAME=pull_request BASE_SHA="$base" HEAD_SHA="$setup"
git rm -q ansible/setup.yml
git -c core.hooksPath=/dev/null commit -qm 'refactor: 설치 삭제'
check true EVENT_NAME=push BEFORE_SHA="$setup" AFTER_SHA="$(git rev-parse HEAD)"
check true EVENT_NAME=push BEFORE_SHA=0000000000000000000000000000000000000000 AFTER_SHA="$docs"
check true EVENT_NAME=push BEFORE_SHA=missing AFTER_SHA="$docs"
check true EVENT_NAME=schedule
check true EVENT_NAME=workflow_dispatch
# PR의 base 브랜치에서만 바뀐 설치 파일은 PR 변경으로 오인하지 않는다.
git checkout -q -b base-branch "$base"
mkdir -p ansible
printf 'base only\n' >ansible/base.yml
git add .
git -c core.hooksPath=/dev/null commit -qm 'feat: 기준 브랜치 설치'
check false EVENT_NAME=pull_request BASE_SHA="$(git rev-parse HEAD)" HEAD_SHA="$docs"
echo '10/10 통과'

before=$(git rev-parse HEAD)
printf 'marker\n' >.gitignore
git add .gitignore
git -c core.hooksPath=/dev/null commit -qm 'chore: 설치 식별 설정'
after=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$before" AFTER_SHA="$after"
