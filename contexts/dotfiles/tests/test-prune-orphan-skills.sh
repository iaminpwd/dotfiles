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

# 2. pruned-all-symlinks: 도메인 목록에 없고 내부가 전부 심볼릭 링크면 안전하게 삭제된다.
mkdir -p "$SKILLS/removed-domain"
ln -s "$TMP/somewhere/SKILL.md" "$SKILLS/removed-domain/SKILL.md"
ln -s "$TMP/somewhere/references" "$SKILLS/removed-domain/references"

# 3. fail-foreign-real-file: 도메인 목록에 없어도 실제 파일이 하나라도 섞여 있으면 보존한다.
mkdir -p "$SKILLS/my-own-skill"
ln -s "$TMP/somewhere/SKILL.md" "$SKILLS/my-own-skill/SKILL.md"
echo "사용자가 직접 만든 실제 파일" >"$SKILLS/my-own-skill/notes.txt"

# 4. pruned-empty: 도메인 목록에 없고 비어 있으면 안전하게(잃을 게 없으므로) 삭제된다.
mkdir -p "$SKILLS/empty-orphan"

OUT=$(bash "$SCRIPT" "$SKILLS" aws k8s 2>&1)

if [ -d "$SKILLS/aws" ] && [ -f "$SKILLS/aws/not-a-symlink.txt" ]; then
  report "ok-valid-domain-kept (유효 도메인은 후보 제외, 그대로 보존)" 0
else
  report "ok-valid-domain-kept (유효 도메인은 후보 제외, 그대로 보존)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

if [ ! -e "$SKILLS/removed-domain" ] && grep -qF "[PRUNED]" <<<"$OUT"; then
  report "pruned-all-symlinks (전부 심볼릭 링크면 삭제)" 0
else
  report "pruned-all-symlinks (전부 심볼릭 링크면 삭제)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

if [ -d "$SKILLS/my-own-skill" ] && [ -f "$SKILLS/my-own-skill/notes.txt" ] && grep -qF "[SKIP]" <<<"$OUT"; then
  report "fail-foreign-real-file (실제 파일이 섞여 있으면 보존 + 경고)" 0
else
  report "fail-foreign-real-file (실제 파일이 섞여 있으면 보존 + 경고)" 1 "$(ls -la "$SKILLS/my-own-skill" 2>&1)"
fi

if [ ! -e "$SKILLS/empty-orphan" ]; then
  report "pruned-empty (빈 고아 폴더는 삭제)" 0
else
  report "pruned-empty (빈 고아 폴더는 삭제)" 1 "$(ls -la "$SKILLS" 2>&1)"
fi

# 5. ok-missing-skills-dir: skills 디렉토리 자체가 없으면 무동작 + exit 0.
status=0
bash "$SCRIPT" "$TMP/does-not-exist" aws || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-missing-skills-dir (skills 디렉토리 없으면 무동작 + exit 0)" 0
else
  report "ok-missing-skills-dir (skills 디렉토리 없으면 무동작 + exit 0)" 1 "exit=$status"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
