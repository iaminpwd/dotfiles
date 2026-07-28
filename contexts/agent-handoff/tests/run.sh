#!/usr/bin/env bash
# agent-handoff 검증기 회귀 테스트
# 각 케이스는 프로토콜이 실제로 뚫렸던 상태(트리거 미해제, task-id 누락, 왕복 상한
# 무력화)를 재현한다. handoff-check.sh 를 수정할 때 기존 판정이 조용히 죽지 않는지
# 확인하는 것이 목적이다.
#
# 픽스처 파일은 저장소에 고정하되, 실행 레이아웃은 임시 디렉토리에 조립한다.
# 통신 파일명(Claude-to-Gemini.md 등)과 .agent-state/ 는 전역 ignore 대상이라
# 그 이름 그대로 저장소에 커밋할 수 없기 때문이다.
#
# 사용: bash ~/dotfiles/contexts/agent-handoff/tests/run.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TESTS_DIR/../scripts/handoff-check.sh"
FIXTURES="$TESTS_DIR/fixtures"
BLUEPRINT="Claude-to-Gemini.md"
REPORT="Gemini-to-Claude.md"
ARCHIVE=".agent-state/handoff-archive"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAILED=0
echo "=== agent-handoff 검증기 회귀 테스트 ==="

# check <케이스명> <기대 종료코드> <리포트에 포함되어야 할 문구> <대상 루트> [추가 플래그]
check() {
  local name=$1 want_code=$2 want_text=$3 root=$4 flag=${5:-}
  local out code=0
  if [ -n "$flag" ]; then
    out=$(bash "$SCRIPT" "$flag" "$root" 2>&1) || code=$?
  else
    out=$(bash "$SCRIPT" "$root" 2>&1) || code=$?
  fi
  if [ "$code" -eq "$want_code" ] && { [ -z "$want_text" ] || [[ "$out" == *"$want_text"* ]]; }; then
    printf '  PASS  %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' "$name"
    printf '        기대: exit=%s, 출력에 %s 포함\n' "$want_code" "${want_text:-(무관)}"
    printf '        실제: exit=%s\n' "$code"
    printf '          %s\n' "${out//$'\n'/$'\n          '}"
  fi
}

# check_verify <케이스명> <기대 종료코드> <설계도 픽스처>
check_verify() {
  local name=$1 want_code=$2 fixture=$3
  local root="$TMP/$name" out code=0
  mkdir -p "$root"
  : >"$root/marker.txt"
  cp "$FIXTURES/$fixture" "$root/$BLUEPRINT"
  out=$(bash "$SCRIPT" --run-verification "$root/$BLUEPRINT" "$root" 2>&1) || code=$?
  if [ "$code" -eq "$want_code" ]; then
    printf '  PASS  %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' "$name"
    printf '        기대: exit=%s / 실제: exit=%s\n' "$want_code" "$code"
    printf '          %s\n' "${out//$'\n'/$'\n          '}"
  fi
}

# 1. 산출물이 없는 저장소: 전역 훅에서 호출되므로 조용히 통과해야 한다.
mkdir -p "$TMP/ok-idle"
check "ok-idle" 0 "" "$TMP/ok-idle"

# 2. 설계도만 존재: 실행자 차례인 정상 상태.
mkdir -p "$TMP/ok-blueprint-pending"
cp "$FIXTURES/blueprint-ok.md" "$TMP/ok-blueprint-pending/$BLUEPRINT"
check "ok-blueprint-pending" 0 "핸드오프 상태 검사 통과" "$TMP/ok-blueprint-pending"

# 3. 통신 파일 동시 존재: Consume & Clear 누락으로 트리거가 해제되지 않은 상태.
mkdir -p "$TMP/fail-both-present"
cp "$FIXTURES/blueprint-ok.md" "$TMP/fail-both-present/$BLUEPRINT"
cp "$FIXTURES/report-ok.md" "$TMP/fail-both-present/$REPORT"
check "fail-both-present" 1 "동시에 존재" "$TMP/fail-both-present"

# 4. task-id 누락: 아키텍트가 아카이브 경로를 확정할 수 없다.
mkdir -p "$TMP/fail-missing-task-id"
cp "$FIXTURES/report-no-task-id.md" "$TMP/fail-missing-task-id/$REPORT"
check "fail-missing-task-id" 1 "task-id" "$TMP/fail-missing-task-id"

# 5. 3왕복 상한 초과: 같은 task-id 로 7개 파일이 쌓인 상태.
mkdir -p "$TMP/fail-roundtrip-exceeded/$ARCHIVE/20260728_000000"
for i in 1 2 3 4 5 6 7; do
  : >"$TMP/fail-roundtrip-exceeded/$ARCHIVE/20260728_000000/f${i}.md"
done
check "fail-roundtrip-exceeded" 1 "3왕복 상한 초과" "$TMP/fail-roundtrip-exceeded"

# 6. task-id 승계 누락 의심: 왕복마다 새 폴더가 생겨 상한이 영원히 발동하지 않는 상태
#    (2026-07-27~28 실측에서 실제로 이 형태였다).
for id in 20260727_192905 20260727_194123 20260728_002128; do
  mkdir -p "$TMP/warn-not-inherited/$ARCHIVE/$id"
  : >"$TMP/warn-not-inherited/$ARCHIVE/$id/blueprint.md"
  : >"$TMP/warn-not-inherited/$ARCHIVE/$id/report.md"
done
check "warn-task-id-not-inherited" 0 "1왕복(파일 2개 이하)" "$TMP/warn-not-inherited"

# 7. 아카이브 폴더명 형식 위반.
mkdir -p "$TMP/warn-bad-dirname/$ARCHIVE/not-a-timestamp"
: >"$TMP/warn-bad-dirname/$ARCHIVE/not-a-timestamp/blueprint.md"
check "warn-bad-dirname" 0 "형식이 아닙니다" "$TMP/warn-bad-dirname"

# 8. 커밋 게이트에서는 3왕복 상한만 경고로 내려 커밋을 막지 않는다.
check "commit-gate-roundtrip-warning" 0 "커밋은 막지 않습니다" "$TMP/fail-roundtrip-exceeded" "--commit-gate"

# 9. 강등은 상한에만 적용된다. 트리거 미해제는 커밋 게이트에서도 그대로 차단해야 한다.
check "commit-gate-both-present-blocks" 1 "동시에 존재" "$TMP/fail-both-present" "--commit-gate"

# 10~11. 설계도 검증 블록 재실행: 통과/실패가 종료 코드로 그대로 전달되어야 한다.
check_verify "verification-runner-pass" 0 "blueprint-ok.md"
check_verify "verification-runner-fail" 1 "blueprint-failing-verification.md"

# 12~14. 배포 드리프트: 배포 직후엔 일치(0), 배포본이 변조되면 불일치(1), 재배포로 복구(0).
DEPLOY="$TESTS_DIR/../scripts/deploy.sh"
DEPLOY_ROOT="$TMP/deploy"
deploy_check() {
  local name=$1 want_code=$2 code=0
  CLAUDE_SKILL_DIR="$DEPLOY_ROOT/claude" GEMINI_SKILL_DIR="$DEPLOY_ROOT/gemini" \
    bash "$DEPLOY" --check >/dev/null 2>&1 || code=$?
  if [ "$code" -eq "$want_code" ]; then
    printf '  PASS  %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n        기대: exit=%s / 실제: exit=%s\n' "$name" "$want_code" "$code"
  fi
}

CLAUDE_SKILL_DIR="$DEPLOY_ROOT/claude" GEMINI_SKILL_DIR="$DEPLOY_ROOT/gemini" \
  bash "$DEPLOY" >/dev/null
deploy_check "deploy-check-in-sync" 0

echo "# 배포본만 변조" >>"$DEPLOY_ROOT/gemini/SKILL.md"
deploy_check "deploy-check-detects-drift" 1

CLAUDE_SKILL_DIR="$DEPLOY_ROOT/claude" GEMINI_SKILL_DIR="$DEPLOY_ROOT/gemini" \
  bash "$DEPLOY" >/dev/null
deploy_check "deploy-check-after-redeploy" 0

echo "======================================================"
if [ "$FAILED" -eq 0 ]; then
  echo "=== agent-handoff 회귀 테스트 통과 ==="
  exit 0
fi
echo "=== agent-handoff 회귀 테스트 실패: ${FAILED}건 ==="
exit 1
