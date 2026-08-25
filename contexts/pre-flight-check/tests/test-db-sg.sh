#!/usr/bin/env bash
# test-db-sg.sh
#
# validate_terraform() 내부에서 실제로 커밋을 막는 하드 게이트인데(bin/linters/
# db-sg-checker.sh, bin/lib/pfc-iac-checks.sh 의 `return 1`) fixture 가 없었다.
# RS="" 문단 스캔이라 "DB 포트(3306/5432)와
# 0.0.0.0 이 같은 블록(빈 줄로 안 나뉨)에 있을 때만" 걸려야 하고, 서로 다른
# 블록에 나뉘어 있으면 걸리면 안 된다 — 이 문단 경계 판정이 깨지기 쉬운 지점이라
# ok-baseline 에 일부러 무관한 0.0.0.0 블록(443 웹 SG)을 같이 넣어 오탐을
# 검증한다. (픽스처 주석에도 검사 대상 리터럴 문자열을 쓰지 않는다 — 주석과
# 코드가 같은 문단에 있으면 주석 자체가 오탐을 유발하기 때문이다.)
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-db-sg.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

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

echo "--- DB 보안 그룹 아키텍처 검사 (db-sg-checker.sh) ---"

DB_SG_SCRIPT="$REPO_ROOT/bin/linters/db-sg-checker.sh"
DB_SG_FIXTURES="$TESTS_DIR/fixtures-db-sg"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/ok-baseline" >/dev/null 2>&1 || code=$?
report "ok-baseline (DB 포트가 WAS SG로만 한정)" "$([ "$code" -eq 0 ] && echo 0 || echo 1)" "기대 exit=0 / 실제 exit=$code"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-open-cidr" >/dev/null 2>&1 || code=$?
report "fail-open-cidr (DB 포트가 0.0.0.0/0에 노출)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

# 아래 셋은 블록 단위 판정으로 바꾸면서 드러난 축들이다. 위 두 픽스처만으로는
# "정상 egress를 오탐하는가"와 "인그레스를 여는 다른 문법을 미탐하는가"를 못 잡는다.
code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/ok-egress-open" >/dev/null 2>&1 || code=$?
report "ok-egress-open (정상 egress 0.0.0.0/0을 오탐하지 않음)" "$([ "$code" -eq 0 ] && echo 0 || echo 1)" "기대 exit=0 / 실제 exit=$code"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-dynamic-ingress" >/dev/null 2>&1 || code=$?
report "fail-dynamic-ingress (dynamic \"ingress\" 블록의 개방 탐지)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-sg-rule-ingress" >/dev/null 2>&1 || code=$?
report "fail-sg-rule-ingress (aws_security_group_rule type=ingress 탐지)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

# 위 케이스의 짝. aws_security_group_rule 은 진입 조건에 방향과 무관하게 걸리므로,
# type = "egress" 를 대상에서 빼는 is_egress 판정이 실제로 동작해야 한다. 이 픽스처가
# 없던 동안 그 경로 전체가 미검증이라 is_egress 를 0 으로 못박아도 통과했다(뮤테이션 확인).
# ok-egress-open 은 인라인 egress 블록이라 애초에 블록 진입 자체를 안 해 대체재가 못 된다.
code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/ok-sg-rule-egress" >/dev/null 2>&1 || code=$?
report "ok-sg-rule-egress (aws_security_group_rule type=egress 는 제외)" "$([ "$code" -eq 0 ] && echo 0 || echo 1)" "기대 exit=0 / 실제 exit=$code"

# 아래 넷은 "포트 리터럴이 안 보이는" 개방 형태들이다. 예전 판정은 블록 안에서
# 3306/5432 숫자와 IPv4 전체 대역 리터럴만 찾았기 때문에, DB 포트만 콕 집어 연
# 규칙보다 오히려 더 심한 위반이 통과했다(실측: 전 포트 개방 exit 0).
code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-port-range" >/dev/null 2>&1 || code=$?
report "fail-port-range (포트 범위로 DB 포트를 포함해 개방)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-all-protocol" >/dev/null 2>&1 || code=$?
report "fail-all-protocol (모든 프로토콜 개방, 포트 인자는 0)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-ipv6-open" >/dev/null 2>&1 || code=$?
report "fail-ipv6-open (IPv6 전체 대역 개방)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

# 위 fail-port-range 의 짝. 범위 판정이 "범위가 있으면 무조건 위반"으로 퇴화하면
# DB 포트를 포함하지 않는 정상 웹 SG 까지 막히므로 반대 방향도 함께 고정한다.
code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/ok-web-port-range" >/dev/null 2>&1 || code=$?
report "ok-web-port-range (DB 포트를 포함하지 않는 범위는 오탐 없음)" "$([ "$code" -eq 0 ] && echo 0 || echo 1)" "기대 exit=0 / 실제 exit=$code"

# -----------------------------------------------------------------------------
# 저장소 루트 스캔 시 회귀 픽스처 제외 (validate_terraform 의 실제 호출 형태)
# -----------------------------------------------------------------------------
# 위 5개는 픽스처 디렉토리를 "직접 지목"해 호출한다. 그런데 실제 커밋 경로에서는
# pfc-iac-checks.sh 의 validate_terraform 이 저장소 루트(".")를 통째로 넘기므로, 그때
# 자기 저장소의 의도적 위반 픽스처가 그대로 잡혀 무관한 커밋이 영구 차단됐다(실측:
# fixtures-db-sg 의 fail-* 3건 신고). 같은 함수의 checkov(--skip-path 'tests/fixtures')와
# validate_security 의 trivy(--skip-dirs '**/tests/fixtures*')는 이미 제외하고 있었다.
#
# 아래는 그 두 방향을 같이 고정한다. 제외만 검증하면 "전부 무시"로 퇴화해도 통과하므로,
# 같은 위반이 일반 경로에 있을 때는 반드시 잡히는지도 함께 본다.
SCAN_TMP=$(mktemp -d)
trap 'rm -rf "$SCAN_TMP"' EXIT

write_violation() {
  mkdir -p "$1"
  cat >"$1/main.tf" <<'EOF'
resource "aws_security_group" "db" {
  name = "db-sg"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
EOF
}

write_violation "$SCAN_TMP/repo/contexts/skill/tests/fixtures-db-sg/fail-open-cidr"
code=0
bash "$DB_SG_SCRIPT" "$SCAN_TMP/repo" >/dev/null 2>&1 || code=$?
report "root-scan-skips-fixtures (루트 스캔은 tests/fixtures 하위 위반을 무시)" \
  "$([ "$code" -eq 0 ] && echo 0 || echo 1)" "기대 exit=0 / 실제 exit=$code"

write_violation "$SCAN_TMP/repo/infra"
code=0
bash "$DB_SG_SCRIPT" "$SCAN_TMP/repo" >/dev/null 2>&1 || code=$?
report "root-scan-detects-real-code (제외가 과하지 않음: 일반 경로 위반은 검출)" \
  "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
