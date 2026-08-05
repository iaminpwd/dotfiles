#!/usr/bin/env bash
# test-pre-commit-hook.sh
#
# git/.githooks/pre-commit은 bin/*.sh 와 달리 test-coverage-check.sh 게이트 밖에 있다.
# 그 사각지대에서 BIN_REMINDERS 재현 명령 조립 로직이 깨질 수 있다: 사람이 읽을 설명
# 문구 "run.sh (전체 — ...)"를 그대로 커맨드 문자열에 이어붙이면, 출력된 줄을 그대로
# 복붙했을 때 괄호 때문에 셸 문법 오류가 난다. 이 스위트는 그 재현 명령이 실제로
# 유효한 셸 명령인지와, 스테이징된 파일이 디스크에서 사라진 경우를 막는 보안 가드를
# 고정한다.
#
# pre-flight-check.sh 본체(trivy/checkov/terraform 등 무거운 외부 도구 파이프라인)는
# 이 훅의 검증 대상이 아니므로, 픽스처 저장소 안에 exit 0만 하는 스텁으로 교체해
# 훅 자체의 오케스트레이션 로직만 격리해서 검증한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-pre-commit-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/git/.githooks/pre-commit"

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

# BIN_REMINDERS 블록은 "$(basename "$REPO_ROOT")" = "dotfiles" 일 때만 활성화되고,
# 하단의 실제 검증 실행부는 그 조건에서 REPO_ROOT/bin/hooks/pre-flight-check.sh 를
# 우선 사용한다. 그 자리에 exit 0 스텁을 심어두면 무거운 실제 파이프라인을 타지 않고도
# 두 로직을 함께 검증할 수 있다.
FIXTURE_REPO="$TMP/dotfiles"
mkdir -p "$FIXTURE_REPO/bin/hooks"
git -C "$FIXTURE_REPO" init -q
git -C "$FIXTURE_REPO" config user.email "test@example.com"
git -C "$FIXTURE_REPO" config user.name "Test"

cat >"$FIXTURE_REPO/bin/hooks/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
echo "[STUB] pre-flight-check.sh 스텁 실행됨"
exit 0
EOF
chmod +x "$FIXTURE_REPO/bin/hooks/pre-flight-check.sh"
git -C "$FIXTURE_REPO" add bin/hooks/pre-flight-check.sh
# 이 샌드박스는 core.hooksPath가 전역으로 이 저장소의 git/.githooks를 가리키고 있어,
# 훅 격리 없이 커밋하면 픽스처 셋업 중에 실제 훅이 재귀적으로 발동해 출력이 오염된다.
# 테스트 대상 SUT(=아래 run_hook_allow_fail 이 명시적으로 호출하는 $HOOK)와 무관한
# 셋업 커밋이므로 훅을 꺼서 격리한다.
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "chore: 초기 스텁 커밋"

run_hook_allow_fail() {
  local status=0
  (cd "$FIXTURE_REPO" && bash "$HOOK") >"$TMP/out" 2>&1 || status=$?
  echo "$status"
}

echo "=== pre-commit 훅 오케스트레이션 로직 회귀 테스트 ==="

# 1. bin/hooks/pre-flight-check.sh 와 bin/linters/container-hardening-gate.sh 를
#    동시에 스테이징하면, "재현 명령" 안내에 두 케이스가 모두 나오고 각 줄이 그대로
#    실행 가능한(파싱 에러 없는) 셸 명령이어야 한다.
mkdir -p "$FIXTURE_REPO/bin/linters"
# 초기 커밋과 내용이 완전히 같으면 git diff --cached 에 아예 안 잡혀 이 case가
# 검증되지 않으므로, 한 줄을 더해 실제 스테이징된 변경으로 만든다.
cat >"$FIXTURE_REPO/bin/hooks/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
echo "[STUB] pre-flight-check.sh 스텁 실행됨 (case1)"
exit 0
EOF
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/linters/container-hardening-gate.sh"
git -C "$FIXTURE_REPO" add bin/hooks/pre-flight-check.sh bin/linters/container-hardening-gate.sh

status=$(run_hook_allow_fail)
OUT="$(cat "$TMP/out")"
REMINDER_LINES=$(grep -E '^\s+bash .*/tests/run\.sh' "$TMP/out" || true)
REMINDER_COUNT=$(printf '%s\n' "$REMINDER_LINES" | grep -c . || true)

# pre-flight-check.sh 전용 case와 bin/linters/*.sh 캐치올 case 둘 다 걸려야 하므로 2줄이어야 한다.
if [ "$status" -eq 0 ] && [ "$REMINDER_COUNT" -eq 2 ] && ! grep -qF '(' <<<"$REMINDER_LINES"; then
  # 출력된 재현 명령 줄들을 그대로 셸에 넣어 파싱 에러(예: 괄호로 인한 syntax error)가
  # 없는지 실제로 검증한다. 스텁이 exit 0 이므로 명령 자체는 실행돼도 안전하다.
  PARSE_OK=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    bash -n <(printf '%s\n' "$line") 2>/dev/null || PARSE_OK=0
  done <<<"$REMINDER_LINES"
  if [ "$PARSE_OK" -eq 1 ]; then
    report "reminder-valid-syntax (재현 명령에 괄호 없이 유효한 셸 문법)" 0
  else
    report "reminder-valid-syntax (재현 명령에 괄호 없이 유효한 셸 문법)" 1 "$REMINDER_LINES"
  fi
else
  report "reminder-valid-syntax (재현 명령에 괄호 없이 유효한 셸 문법)" 1 "exit=$status out=$OUT"
fi

git -C "$FIXTURE_REPO" reset -q

# 2. 무관한 파일만 변경하면 BIN_REMINDERS 안내 자체가 나오지 않아야 한다(오탐 방지).
echo "hello" >"$FIXTURE_REPO/README.md"
git -C "$FIXTURE_REPO" add README.md
status=$(run_hook_allow_fail)
if [ "$status" -eq 0 ] && ! grep -qF "bin/ 핵심 검증 로직 변경이 감지되었습니다" "$TMP/out"; then
  report "no-reminder-on-unrelated-change (무관한 변경은 안내 없음)" 0
else
  report "no-reminder-on-unrelated-change (무관한 변경은 안내 없음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi
git -C "$FIXTURE_REPO" reset -q
rm -f "$FIXTURE_REPO/README.md"

# 3. [보안] 스테이징은 됐는데 디스크에서 파일이 사라지고 'git rm --cached'도 안 했으면
#    시크릿 유출 위험 경고와 함께 커밋을 차단해야 한다.
echo "secret-ish content" >"$FIXTURE_REPO/ghost.txt"
git -C "$FIXTURE_REPO" add ghost.txt
rm -f "$FIXTURE_REPO/ghost.txt"
status=$(run_hook_allow_fail)
if [ "$status" -eq 1 ] && grep -qF "디스크에 존재하지 않지만" "$TMP/out"; then
  report "fail-staged-but-deleted (디스크 삭제·스테이징 잔류 차단)" 0
else
  report "fail-staged-but-deleted (디스크 삭제·스테이징 잔류 차단)" 1 "exit=$status out=$(cat "$TMP/out")"
fi
git -C "$FIXTURE_REPO" reset -q -- ghost.txt 2>/dev/null || true

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
