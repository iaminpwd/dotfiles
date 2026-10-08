#!/usr/bin/env bash
# bootstrap-smoke의 2차 실행이 "성공"뿐 아니라 실제 changed=0을 강제하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CI="$ROOT/.github/workflows/ci.yml"
ASSERT="$ROOT/.github/scripts/assert-idempotent-ansible-recap.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SECOND_STEP=$(awk '
  /- name: Bootstrap \(2nd run - idempotency check\)/ { capture=1 }
  capture { print }
  capture && /^      - name:/ && !/Bootstrap \(2nd run - idempotency check\)/ { exit }
' "$CI")

# shellcheck disable=SC2016 # workflow 안의 literal $SECOND_BOOTSTRAP_LOG 참조를 검사한다.
if ! grep -q 'bootstrap-second\.log' <<<"$SECOND_STEP" ||
  ! grep -q 'tee "\$SECOND_BOOTSTRAP_LOG"' <<<"$SECOND_STEP" ||
  ! grep -q 'assert-idempotent-ansible-recap.sh' <<<"$SECOND_STEP"; then
  echo 'FAIL: 2차 bootstrap이 changed=0을 검사하지 않아 비멱등 변경도 CI에서 GREEN이 될 수 있습니다.'
  exit 1
fi

if [ ! -f "$ASSERT" ]; then
  echo 'FAIL: Ansible recap의 changed=0을 검증하는 스크립트가 없습니다.'
  exit 1
fi

cat >"$TMP/good.log" <<'EOF'
PLAY RECAP *********************************************************************
localhost                  : ok=57   changed=0    unreachable=0    failed=0    skipped=11
EOF
bash "$ASSERT" "$TMP/good.log"

cat >"$TMP/bad.log" <<'EOF'
PLAY RECAP *********************************************************************
localhost                  : ok=57   changed=2    unreachable=0    failed=0    skipped=11
EOF
status=0
bash "$ASSERT" "$TMP/bad.log" >"$TMP/bad.out" 2>&1 || status=$?
[ "$status" -ne 0 ] || {
  echo 'FAIL: changed>0 recap이 idempotency gate를 통과했습니다.'
  exit 1
}
grep -q 'changed=2' "$TMP/bad.out"

cat >"$TMP/missing.log" <<'EOF'
bootstrap completed without an Ansible recap
EOF
status=0
bash "$ASSERT" "$TMP/missing.log" >"$TMP/missing.out" 2>&1 || status=$?
[ "$status" -ne 0 ] || {
  echo 'FAIL: recap이 없는 로그가 idempotency gate를 통과했습니다.'
  exit 1
}

# Ansible이 실제 PLAY RECAP을 출력하지 않았는데 일반 진단 로그에
# 동일한 카운터 문자열이 있는 경우도 성공으로 오인해서는 안 된다.
# exit 0으로 끝난 bootstrap에서 Ansible 실행 자체가 생략된 회귀를 차단한다.
cat >"$TMP/fake-recap.log" <<'EOF'
[INFO] package summary: ok=57 changed=0 unreachable=0 failed=0 skipped=11
EOF
status=0
bash "$ASSERT" "$TMP/fake-recap.log" >"$TMP/fake-recap.out" 2>&1 || status=$?
[ "$status" -ne 0 ] || {
  echo 'FAIL: PLAY RECAP 헤더가 없는 일반 카운터 출력이 idempotency gate를 통과했습니다.'
  exit 1
}

echo 'PASS: 2차 bootstrap은 Ansible changed=0을 실제로 강제함'
