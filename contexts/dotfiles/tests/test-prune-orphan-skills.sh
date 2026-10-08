#!/usr/bin/env bash
# test-prune-orphan-skills.sh
#
# prune-orphan-skills.sh는 ai_agent 롤이 ~/.claude/skills, ~/.gemini/config/skills에서
# contexts/ 도메인 목록에 없는 "고아" 폴더를 정리하는 스크립트다. 이 두 디렉토리는
# dotfiles 전용이 아니라 Claude Code/Gemini의 범용 글로벌 스킬 레지스트리라서, 이름이
# 우연히 도메인 목록에 없다고 무조건 지우면 사용자가 직접 만들었거나 다른 도구로 설치한
# 스킬까지 확인 없이 사라진다(실측: ~/.config 폴딩 사고와 같은 클래스). "폴더 내부가
# 전부 심볼릭 링크일 때만 지운다"는 소유권 판정이 이 스크립트의 핵심이라, 그 판정이
# 깨지면 곧바로 사용자 데이터 유실로 이어진다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-prune-orphan-skills.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/utils/prune-orphan-skills.sh"

PASS_COUNT=0
FAIL_COUNT=0

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== prune-orphan-skills.sh 고아 스킬 폴더 소유권 판정 회귀 테스트 ==="

SKILLS="$TMP/skills"
mkdir -p "$SKILLS"

# 1. ok-valid-domain-kept: 유효 도메인 이름과 일치하면 실제 파일이 섞여 있어도 후보에도 안 오른다.
mkdir -p "$SKILLS/aws"
echo "실제 데이터" >"$SKILLS/aws/not-a-symlink.txt"

# 2. pruned-repo-owned-symlinks: 도메인 목록에 없고, 링크 대상이 이 저장소 contexts/
#    아래의 제거된 도메인이면 ai_agent 롤이 만들었던 잔재이므로 안전하게 삭제한다.
mkdir -p "$SKILLS/removed-domain"
ln -s "$REPO_ROOT/contexts/removed-domain/SKILL.md" "$SKILLS/removed-domain/SKILL.md"
ln -s "$REPO_ROOT/contexts/removed-domain/references" "$SKILLS/removed-domain/references"

# 3. fail-foreign-all-symlinks: 공유 글로벌 레지스트리에는 사용자가 직접 만든 스킬도
#    존재할 수 있다. 파일이 전부 symlink여도 링크 대상이 이 저장소 contexts/ 밖이면
#    dotfiles 소유로 오판해 삭제하면 안 된다.
mkdir -p "$TMP/foreign-source" "$SKILLS/my-linked-skill"
echo "foreign skill" >"$TMP/foreign-source/SKILL.md"
mkdir -p "$TMP/foreign-source/references"
ln -s "$TMP/foreign-source/SKILL.md" "$SKILLS/my-linked-skill/SKILL.md"
ln -s "$TMP/foreign-source/references" "$SKILLS/my-linked-skill/references"

# 4. fail-user-alias-to-managed-context: 사용자가 repo의 기존 스킬을 별칭 이름으로
#    직접 등록할 수도 있다. 링크 대상이 contexts/aws 아래라는 이유만으로 aws-alias를
#    ai_agent가 만든 폴더라고 볼 수 없다. role은 skills/<domain> -> contexts/<same-domain>
#    형태만 만들므로 이름과 source domain이 다르면 외부/사용자 소유로 보존해야 한다.
mkdir -p "$SKILLS/aws-alias"
ln -s "$REPO_ROOT/contexts/aws/SKILL.md" "$SKILLS/aws-alias/SKILL.md"
ln -s "$REPO_ROOT/contexts/aws/references" "$SKILLS/aws-alias/references"

# 5. fail-foreign-real-file: 도메인 목록에 없어도 실제 파일이 하나라도 섞여 있으면 보존한다.
mkdir -p "$SKILLS/my-own-skill"
ln -s "$TMP/somewhere/SKILL.md" "$SKILLS/my-own-skill/SKILL.md"
echo "사용자가 직접 만든 실제 파일" >"$SKILLS/my-own-skill/notes.txt"

# 6. keep-empty-user-dir: 빈 폴더만으로는 ai_agent가 생성했다는 소유권을 증명하지 못한다.
mkdir -p "$SKILLS/empty-orphan"

# 6a. Even a matching contexts/<domain> source is not proof of ownership
# when the asset name was never deployed by the ai_agent role.
mkdir -p "$SKILLS/custom-only" "$SKILLS/managed-plus-custom" "$SKILLS/managed-plus-hidden"
ln -s "$REPO_ROOT/contexts/custom-only/notes.md" "$SKILLS/custom-only/notes.md"
ln -s "$REPO_ROOT/contexts/managed-plus-custom/SKILL.md" "$SKILLS/managed-plus-custom/SKILL.md"
ln -s "$REPO_ROOT/contexts/managed-plus-custom/notes.md" "$SKILLS/managed-plus-custom/notes.md"
ln -s "$REPO_ROOT/contexts/managed-plus-hidden/SKILL.md" "$SKILLS/managed-plus-hidden/SKILL.md"
printf 'my hidden file\n' >"$SKILLS/managed-plus-hidden/.private-note"

OUT=$(bash "$SCRIPT" "$SKILLS" aws k8s 2>&1)

if [ -d "$SKILLS/aws" ] && [ -f "$SKILLS/aws/not-a-symlink.txt" ]; then
  report "ok-valid-domain-kept (유효 도메인은 후보 제외, 그대로 보존)" 0
else
  report "ok-valid-domain-kept (유효 도메인은 후보 제외, 그대로 보존)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

if [ ! -e "$SKILLS/removed-domain" ] && grep -qF "[PRUNED]" <<<"$OUT"; then
  report "pruned-repo-owned-symlinks (저장소 contexts/를 가리키는 고아 링크는 삭제)" 0
else
  report "pruned-repo-owned-symlinks (저장소 contexts/를 가리키는 고아 링크는 삭제)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

if [ -d "$SKILLS/my-linked-skill" ] &&
  [ -L "$SKILLS/my-linked-skill/SKILL.md" ] &&
  [ -L "$SKILLS/my-linked-skill/references" ]; then
  report "fail-foreign-all-symlinks (외부 대상을 가리키는 symlink-only 스킬은 보존)" 0
else
  report "fail-foreign-all-symlinks (외부 대상을 가리키는 symlink-only 스킬은 보존)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

if [ -d "$SKILLS/aws-alias" ] &&
  [ -L "$SKILLS/aws-alias/SKILL.md" ] &&
  [ -L "$SKILLS/aws-alias/references" ]; then
  report "fail-user-alias-to-managed-context (다른 이름의 사용자 별칭 스킬 보존)" 0
else
  report "fail-user-alias-to-managed-context (다른 이름의 사용자 별칭 스킬 보존)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

if [ -d "$SKILLS/my-own-skill" ] && [ -f "$SKILLS/my-own-skill/notes.txt" ] && grep -qF "[SKIP]" <<<"$OUT"; then
  report "fail-foreign-real-file (실제 파일이 섞여 있으면 보존 + 경고)" 0
else
  report "fail-foreign-real-file (실제 파일이 섞여 있으면 보존 + 경고)" 1 "$(ls -la "$SKILLS/my-own-skill" 2>&1)"
fi

if [ -d "$SKILLS/empty-orphan" ]; then
  report "keep-empty-user-dir (소유권 불명 빈 폴더는 보존)" 0
else
  report "keep-empty-user-dir (소유권 불명 빈 폴더는 보존)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

# 6a. Custom names and hidden user files must never be treated as old role output.
if [ -L "$SKILLS/custom-only/notes.md" ] &&
  [ -L "$SKILLS/managed-plus-custom/notes.md" ] &&
  [ -L "$SKILLS/managed-plus-custom/SKILL.md" ] &&
  [ -f "$SKILLS/managed-plus-hidden/.private-note" ]; then
  report "keep-custom-assets (임의 에셋 링크 및 숨김 사용자 파일 보존)" 0
else
  report "keep-custom-assets (임의 에셋 링크 및 숨김 사용자 파일 보존)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

# A top-level alias to a skill directory may be managed by another application.
LINKED="$TMP/symlinked-skills"
mkdir -p "$LINKED" "$TMP/external-skill-folder"
ln -s "$REPO_ROOT/contexts/aws/references" "$TMP/external-skill-folder/references"
ln -s "$TMP/external-skill-folder" "$LINKED/aws"
OUT_LINK=$(bash "$SCRIPT" "$LINKED" aws k8s 2>&1)
if [ -L "$LINKED/aws" ] && [ -L "$TMP/external-skill-folder/references" ]; then
  report "keep-linked-skill-dir (외부 폴더로 연결된 도메인 링크를 탐색·삭제하지 않음)" 0
else
  report "keep-linked-skill-dir (외부 폴더로 연결된 도메인 링크를 탐색·삭제하지 않음)" 1 "output=$OUT_LINK"
fi

# A failed inventory scan must fail closed, not treat a directory as empty.
FAIL_FIND="$TMP/failing-find"
FAIL_DIR="$TMP/unreadable-inventory"
mkdir -p "$FAIL_FIND" "$FAIL_DIR/lost-skill"
ln -s "$REPO_ROOT/contexts/lost-skill/SKILL.md" "$FAIL_DIR/lost-skill/SKILL.md"
printf '#!/bin/sh\nexit 1\n' >"$FAIL_FIND/find"
chmod +x "$FAIL_FIND/find"
OUT_FAIL_FIND=$(PATH="$FAIL_FIND:$PATH" bash "$SCRIPT" "$FAIL_DIR" aws k8s 2>&1)
if [ -L "$FAIL_DIR/lost-skill/SKILL.md" ] &&
  grep -qF "[SKIP]" <<<"$OUT_FAIL_FIND"; then
  report "failed-inventory-preserves-dir (find 실패는 삭제가 아닌 보존)" 0
else
  report "failed-inventory-preserves-dir (find 실패는 삭제가 아닌 보존)" 1 "output=$OUT_FAIL_FIND"
fi

# 7. ok-missing-skills-dir: skills 디렉토리 자체가 없으면 무동작 + exit 0.
status=0
bash "$SCRIPT" "$TMP/does-not-exist" aws || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-missing-skills-dir (skills 디렉토리 없으면 무동작 + exit 0)" 0
else
  report "ok-missing-skills-dir (skills 디렉토리 없으면 무동작 + exit 0)" 1 "exit=$status"
fi

# 8. Existing domain, deleted asset: the installer must not leave its old
#    managed dangling symlink in a global agent registry.
#    A foreign link and an existing managed asset must remain untouched.
STALE_SKILLS="$TMP/stale-skills"
mkdir -p "$STALE_SKILLS/aws" "$TMP/foreign-skill-asset"
# aws/references has been removed from contexts; it used to be a managed asset.
if [ -e "$REPO_ROOT/contexts/aws/references" ]; then
  report "missing-asset-fixture (aws/references must be absent)" 1
else
  ln -s "$REPO_ROOT/contexts/aws/references" "$STALE_SKILLS/aws/references"
  ln -s "$REPO_ROOT/contexts/aws/SKILL.md" "$STALE_SKILLS/aws/SKILL.md"
  ln -s "$TMP/foreign-skill-asset" "$STALE_SKILLS/aws/examples"
  OUT_STALE=$(bash "$SCRIPT" "$STALE_SKILLS" aws k8s 2>&1)
  if [ ! -L "$STALE_SKILLS/aws/references" ] &&
    [ -L "$STALE_SKILLS/aws/SKILL.md" ] &&
    [ -L "$STALE_SKILLS/aws/examples" ] &&
    grep -qF "[PRUNED]" <<<"$OUT_STALE"; then
    report "stale-asset-removed (유효 도메인의 삭제된 관리 에셋만 정리)" 0
  else
    report "stale-asset-removed (유효 도메인의 삭제된 관리 에셋만 정리)" 1 "output=$OUT_STALE"
  fi
  OUT_STALE_2=$(bash "$SCRIPT" "$STALE_SKILLS" aws k8s 2>&1)
  if [ ! -L "$STALE_SKILLS/aws/references" ] &&
    [ -L "$STALE_SKILLS/aws/examples" ] &&
    ! grep -qF "[PRUNED]" <<<"$OUT_STALE_2"; then
    report "stale-asset-idempotent (재실행 후 추가 변경 없음)" 0
  else
    report "stale-asset-idempotent (재실행 후 추가 변경 없음)" 1 "output=$OUT_STALE_2"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
