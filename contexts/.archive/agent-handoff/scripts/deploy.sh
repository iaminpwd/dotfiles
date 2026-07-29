#!/usr/bin/env bash
# deploy.sh - agent-handoff 역할 결합 배포 (배포 로직의 단일 진실 공급원)
#
# 이 스킬은 저장소의 다른 11건과 달리 심볼릭 링크가 아니라 복사본으로 배포된다.
# 두 에이전트에게 서로 다른 역할 파일을 붙여 보내야 하기 때문이다. 그래서 원본을
# 고치고 재배포하지 않으면 양측 런타임이 구버전 조항으로 동작한다(2026-07-27 실측).
# setup.sh 와 pre-commit 훅이 모두 이 스크립트를 호출한다. 배포 명령을 양쪽에
# 복제하면 한쪽만 고쳐져 배포본이 갈린다.
#
# 사용:
#   bash deploy.sh            배포 수행
#   bash deploy.sh --check    배포본과 원본의 일치만 확인 (쓰기 없음, 불일치 시 exit 1)
#
# 테스트는 CLAUDE_SKILL_DIR / GEMINI_SKILL_DIR 로 대상 경로를 바꿔 호출한다.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_SKILL_DIR:-$HOME/.claude/skills/agent-handoff}"
GEMINI_DIR="${GEMINI_SKILL_DIR:-$HOME/.gemini/config/skills/agent-handoff}"

MISSING=""
for part in SKILL.md role.architect.md role.executor.md; do
  [ -f "$SRC_DIR/$part" ] || MISSING="$MISSING $part"
done
if [ -n "$MISSING" ]; then
  echo "❌ [ERROR] agent-handoff 구성 파일 누락:$MISSING" >&2
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  DRIFT=0
  cmp -s <(cat "$SRC_DIR/SKILL.md" "$SRC_DIR/role.architect.md") "$CLAUDE_DIR/SKILL.md" || DRIFT=1
  cmp -s <(cat "$SRC_DIR/SKILL.md" "$SRC_DIR/role.executor.md") "$GEMINI_DIR/SKILL.md" || DRIFT=1
  if [ "$DRIFT" -ne 0 ]; then
    echo "[WARNING] agent-handoff 배포본이 원본과 다릅니다. 재배포가 필요합니다."
    echo "    재배포: bash $SRC_DIR/scripts/deploy.sh"
  fi
  exit "$DRIFT"
fi

mkdir -p "$CLAUDE_DIR" "$GEMINI_DIR"
# 배포 경로가 어떤 이유로든 심볼릭 링크가 되어 있으면 아래 `>` 가 링크를 따라가 링크
# 대상(저장소의 SKILL.md 정본)을 덮어쓴다. 이 경로가 링크였던 이력은 없지만, 한 번
# 발생하면 정본이 소실되므로 쓰기 전에 링크 자체를 제거한다.
rm -f "$CLAUDE_DIR/SKILL.md" "$GEMINI_DIR/SKILL.md"
cat "$SRC_DIR/SKILL.md" "$SRC_DIR/role.architect.md" >"$CLAUDE_DIR/SKILL.md"
cat "$SRC_DIR/SKILL.md" "$SRC_DIR/role.executor.md" >"$GEMINI_DIR/SKILL.md"
echo "   ✅ agent-handoff 역할 결합 배포 완료 (architect / executor)"
