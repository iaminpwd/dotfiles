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
mkdir -p ansible contexts/aws/{references,tests,scripts} contexts/dotfiles/tests
printf 'base\n' >README.md
printf 'reference-v1\n' >contexts/aws/references/010-core.md
printf 'skill-v1\n' >contexts/aws/SKILL.md
printf 'agents-v1\n' >contexts/base.AGENTS.md
printf 'test-v1\n' >contexts/aws/tests/test.sh
printf 'stow-test-v1\n' >contexts/dotfiles/tests/test-stow-toctou.sh
printf 'script-v1\n' >contexts/aws/scripts/check.sh
git add .
git -c core.hooksPath=/dev/null commit -qm 'chore: 초기 상태'
base=$(git rev-parse HEAD)

COUNT=0
check() {
  local expected=$1
  shift
  actual=$(env "$@" bash "$SCRIPT")
  [ "$actual" = "run=$expected" ] || {
    echo "FAIL: $* => $actual"
    exit 1
  }
  COUNT=$((COUNT + 1))
  echo "PASS: $*"
}

# reference 내용만 바뀌면 설치 링크 구조는 동일하다.
printf 'reference-v2\n' >contexts/aws/references/010-core.md
git add .
git -c core.hooksPath=/dev/null commit -qm 'docs: 설명'
docs=$(git rev-parse HEAD)
check false EVENT_NAME=push BEFORE_SHA="$base" AFTER_SHA="$docs"
check false EVENT_NAME=pull_request BASE_SHA="$base" HEAD_SHA="$docs"

# ai_agent Ansible 롤은 references/examples/scripts 디렉터리의 존재 여부를 보고
# 각 스킬 에셋 링크를 생성한다. 따라서 폴더 안의 문서 수정은 smoke 생략 가능하지만
# 폴더 첫 생성/마지막 삭제는 링크 집합 변화이므로 smoke를 반드시 실행해야 한다.
mkdir -p contexts/aws/examples
printf 'first example\n' >contexts/aws/examples/sample.md
git add contexts/aws/examples/sample.md
git -c core.hooksPath=/dev/null commit -qm 'feat: 최초 examples 에셋 추가'
examples_added=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$docs" AFTER_SHA="$examples_added"
check true EVENT_NAME=pull_request BASE_SHA="$docs" HEAD_SHA="$examples_added"

git rm -q contexts/aws/examples/sample.md
git -c core.hooksPath=/dev/null commit -qm 'refactor: examples 에셋 마지막 파일 제거'
examples_deleted=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$examples_added" AFTER_SHA="$examples_deleted"

# SKILL/base.AGENTS 내용 수정은 이미 고정된 symlink의 소스 내용만 바뀌므로 smoke 불필요.
printf 'skill-v2\n' >contexts/aws/SKILL.md
git add .
git -c core.hooksPath=/dev/null commit -qm 'docs: 스킬 설명 수정'
skill_modified=$(git rev-parse HEAD)
check false EVENT_NAME=push BEFORE_SHA="$docs" AFTER_SHA="$skill_modified"

printf 'agents-v2\n' >contexts/base.AGENTS.md
git add .
git -c core.hooksPath=/dev/null commit -qm 'docs: 글로벌 룰 수정'
agents_modified=$(git rev-parse HEAD)
check false EVENT_NAME=push BEFORE_SHA="$skill_modified" AFTER_SHA="$agents_modified"

# tests는 설치 대상이 아니므로 smoke 불필요.
printf 'test-v2\n' >contexts/aws/tests/test.sh
git add .
git -c core.hooksPath=/dev/null commit -qm 'test: 회귀 수정'
test_modified=$(git rev-parse HEAD)
check false EVENT_NAME=push BEFORE_SHA="$agents_modified" AFTER_SHA="$test_modified"

# Stow TOCTOU regression directly participates in Debian/macOS smoke.
# Unlike ordinary non-deployed context tests it must trigger both runners.
printf 'stow-test-v2\n' >contexts/dotfiles/tests/test-stow-toctou.sh
git add .
git -c core.hooksPath=/dev/null commit -qm 'test: Stow 경쟁 조건 회귀 수정'
stow_test_modified=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$test_modified" AFTER_SHA="$stow_test_modified"
check true EVENT_NAME=pull_request BASE_SHA="$test_modified" HEAD_SHA="$stow_test_modified"

# scripts는 ~/.local/bin 배포 대상이라 내용 변경도 bootstrap smoke 대상이다.
printf 'script-v2\n' >contexts/aws/scripts/check.sh
git add .
git -c core.hooksPath=/dev/null commit -qm 'fix: 배포 스크립트 수정'
script_modified=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$stow_test_modified" AFTER_SHA="$script_modified"

# SKILL 추가/삭제는 배포 에셋 존재 여부가 달라지므로 smoke 대상이다.
mkdir -p contexts/new
printf 'new-skill\n' >contexts/new/SKILL.md
git add .
git -c core.hooksPath=/dev/null commit -qm 'feat: 새 스킬 추가'
skill_added=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$script_modified" AFTER_SHA="$skill_added"

git rm -q contexts/new/SKILL.md
git -c core.hooksPath=/dev/null commit -qm 'refactor: 스킬 제거'
skill_deleted=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$skill_added" AFTER_SHA="$skill_deleted"

# base.AGENTS 삭제도 고정 글로벌 링크의 소스가 사라지므로 smoke 대상이다.
git rm -q contexts/base.AGENTS.md
git -c core.hooksPath=/dev/null commit -qm 'refactor: 글로벌 룰 제거'
agents_deleted=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$skill_deleted" AFTER_SHA="$agents_deleted"

printf 'setup\n' >ansible/setup.yml
git add .
git -c core.hooksPath=/dev/null commit -qm 'feat: 설치'
setup=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$agents_deleted" AFTER_SHA="$setup"
check true EVENT_NAME=pull_request BASE_SHA="$agents_deleted" HEAD_SHA="$setup"

git rm -q ansible/setup.yml
git -c core.hooksPath=/dev/null commit -qm 'refactor: 설치 삭제'
setup_deleted=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$setup" AFTER_SHA="$setup_deleted"

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

before=$(git rev-parse HEAD)
printf 'marker\n' >.gitignore
git add .gitignore
git -c core.hooksPath=/dev/null commit -qm 'chore: 설치 식별 설정'
after=$(git rev-parse HEAD)
check true EVENT_NAME=push BEFORE_SHA="$before" AFTER_SHA="$after"

echo "$COUNT/$COUNT 통과"
