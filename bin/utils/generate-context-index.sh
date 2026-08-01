#!/usr/bin/env bash
# generate-context-index.sh - contexts/ 워크스페이스 색인 생성기
#
# 새로 이 저장소를 읽는 사람이 12개 워크스페이스 각각의 SKILL.md를 일일이 열어보지
# 않고도 "어떤 워크스페이스에 어떤 룰 문서가 있는지"를 한 페이지로 훑을 수 있도록,
# 각 SKILL.md의 라우팅 테이블("작업 유형별 참조 문서 라우팅")을 그대로 이어붙인다.
#
# 별도 요약을 새로 작성하지 않고 기존 라우팅 테이블을 SSOT로 재사용하는 이유는
# 무엇이든 두 번 쓰면 한쪽만 고쳐지고 다른 쪽이 낡기 때문이다(contexts/ 전반에
# 걸친 이 저장소의 SSOT 원칙과 동일).
#
# 출력은 stdout이며 파일을 직접 쓰지 않는다(생성 결과와 저장된 contexts/INDEX.md가
# 갈리는지는 prompt-lint.sh 의 check_index_freshness 가 diff로 판정하므로, 이 스크립트가
# 파일을 직접 덮어쓰면 판정 대상 자체가 사라진다).
#
# 사용: bash bin/utils/generate-context-index.sh > contexts/INDEX.md

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONTEXTS_DIR="$REPO_ROOT/contexts"

echo "# Contexts Index"
echo
echo "> 자동 생성 문서입니다. 직접 편집하지 말고 아래 명령으로 재생성하십시오:"
echo "> \`bash bin/utils/generate-context-index.sh > contexts/INDEX.md\`"
echo ">"
echo "> 각 워크스페이스 SKILL.md의 라우팅 테이블을 그대로 모은 색인이므로, 실제 조항 내용은"
echo "> 반드시 해당 참조 문서를 직접 여십시오. 전체 이론적 배경은 [README.md](README.md) 참고."

for skill_dir in "$CONTEXTS_DIR"/*/; do
  skill=$(basename "$skill_dir")
  [ "$skill" = ".archive" ] && continue
  skill_md="${skill_dir}SKILL.md"
  [ -f "$skill_md" ] || continue

  desc=$(awk '/^description:/{getline; gsub(/^[[:space:]]+/,""); print; exit}' "$skill_md")

  echo
  echo "## $skill"
  echo
  [ -n "$desc" ] && echo "$desc"
  echo

  if grep -q "작업 유형별 참조 문서 라우팅" "$skill_md"; then
    awk '
      /작업 유형별 참조 문서 라우팅/ { found=1; next }
      found && /^\|/ { print; in_table=1; next }
      found && in_table && !/^\|/ { exit }
    ' "$skill_md"
  else
    echo "_(라우팅 테이블 없음 — SKILL.md 단일 문서)_"
  fi
done
