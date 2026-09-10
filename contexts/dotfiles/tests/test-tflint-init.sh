#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible" ANSIBLE_LOCAL_TEMP="$TMP/local" ANSIBLE_REMOTE_TEMP="$TMP/remote"
if ! command -v ansible-playbook >/dev/null || ! ansible-playbook --version >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (TFLint 재시도 테스트)'
  exit 0
fi
mkdir -p "$TMP/roles/tflint/tasks" "$TMP/tools"
# 실제 태스크를 실행하되 테스트에서는 재시도 대기만 없앤다.
sed 's/delay: 5/delay: 0/' "$ROOT/ansible/roles/tflint/tasks/main.yml" >"$TMP/roles/tflint/tasks/main.yml"
cat >"$TMP/play.yml" <<'YAML'
- hosts: localhost
  gather_facts: false
  connection: local
  roles:
    - tflint
YAML
cat >"$TMP/tools/tflint" <<'STUB'
#!/usr/bin/env bash
count=$(cat "$ATTEMPTS" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" >"$ATTEMPTS"
if [ "$count" -le "$FAIL_UNTIL" ]; then
  echo '500 Server Error' >&2
  exit 1
fi
echo 'Installing plugin'
STUB
chmod +x "$TMP/tools/tflint"
export PATH="$TMP/tools:$PATH" ATTEMPTS="$TMP/count"
export ANSIBLE_HOME="$TMP/ansible" ANSIBLE_LOCAL_TEMP="$TMP/local" ANSIBLE_REMOTE_TEMP="$TMP/remote"
FAIL_UNTIL=2 ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1 || {
  cat "$TMP/out"
  exit 1
}
[ "$(cat "$ATTEMPTS")" = 3 ]
echo 'PASS: 일시적 오류 후 세 번째 시도 성공'
printf '0\n' >"$ATTEMPTS"
if FAIL_UNTIL=99 ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1; then
  echo 'FAIL: 지속 오류가 통과함'
  exit 1
fi
[ "$(cat "$ATTEMPTS")" = 4 ]
echo 'PASS: 최초 실행과 재시도 3회 실패 시 중단'
