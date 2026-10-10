#!/usr/bin/env bash
# Isolated protocol tests: no real user's hooks, settings or repositories.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin/hooks" "$TMP/bin/lib"
cp "$ROOT/bin/hooks/agent-stop-adapter.sh" "$TMP/bin/hooks/"
cp "$ROOT/bin/lib/jq-resolve.sh" "$TMP/bin/lib/"
cat >"$TMP/bin/hooks/pre-flight-gate-hook.sh" <<'SH'
#!/usr/bin/env bash
input=$(cat)
root=$(jq -r '.cwd' <<<"$input")
printf '%s\n' "$root" >>"$CALL_LOG"
case "$root" in
*/fail)
  printf '%s\n' '{"decision":"block","reason":"fixture failed","hookSpecificOutput":{"additionalContext":"test command: just verify"}}'
  ;;
esac
SH
chmod +x "$TMP/bin/hooks/"*.sh
export CALL_LOG="$TMP/calls"
PASS=0
FAIL=0
check() {
  local name=$1 actual=$2 expression=$3
  if jq -e "$expression" <<<"$actual" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $name: $actual"
  fi
}
ADAPTER="$TMP/bin/hooks/agent-stop-adapter.sh"

out=$(printf '%s' '{"cwd":"/tmp/project ok","stop_hook_active":false}' | "$ADAPTER" codex)
check 'Codex success returns valid nonblocking JSON' "$out" '. == {}'
test "$(tail -1 "$CALL_LOG")" = '/tmp/project ok'
out=$(printf '%s' '{"cwd":"/tmp/fail","stop_hook_active":false}' | "$ADAPTER" codex)
check 'Codex failure requests model continuation with diagnostics' "$out" '.decision == "block" and (.reason | contains("just verify"))'
before=$(wc -l <"$CALL_LOG")
out=$(printf '%s' '{"cwd":"/tmp/fail","stop_hook_active":true}' | "$ADAPTER" codex)
check 'Codex recursive Stop is skipped with valid JSON' "$out" '. == {}'
test "$(wc -l <"$CALL_LOG")" -eq "$before"
out=$(printf '%s' '{}' | "$ADAPTER" codex)
check 'Codex missing workspace cannot silently succeed' "$out" '.decision == "block"'

out=$(printf '%s' '{"workspacePaths":["/tmp/project ok"],"fullyIdle":true,"executionNum":1}' | "$ADAPTER" antigravity)
check 'Antigravity success uses allow' "$out" '.decision == "allow"'
out=$(printf '%s' '{"workspacePaths":["/tmp/project ok","/tmp/fail"],"fullyIdle":true,"executionNum":1}' | "$ADAPTER" antigravity)
check 'Antigravity failure continues and reports selected workspace' "$out" '.decision == "continue" and (.reason | contains("/tmp/fail"))'
before=$(wc -l <"$CALL_LOG")
out=$(printf '%s' '{"workspacePaths":["/tmp/fail"],"fullyIdle":false,"executionNum":1}' | "$ADAPTER" antigravity)
check 'Antigravity unfinished background work defers validation' "$out" '.decision == "continue"'
test "$(wc -l <"$CALL_LOG")" -eq "$before"
out=$(printf '%s' '{"workspacePaths":["/tmp/fail"],"fullyIdle":true,"executionNum":42,"terminationReason":"model_stop"}' | "$ADAPTER" antigravity)
check 'Antigravity executionNum is not a retry-count bypass' "$out" '.decision == "continue"'
out=$(printf '%s' '{"workspacePaths":["/tmp/fail"],"fullyIdle":true,"terminationReason":"max_steps_exceeded"}' | "$ADAPTER" antigravity 2>"$TMP/exhausted")
check 'Antigravity unrecoverable termination is not reentered' "$out" '.decision == "allow"'
grep -q 'before Stop verification passed' "$TMP/exhausted"
out=$(printf '%s' '{}' | "$ADAPTER" antigravity)
check 'Antigravity malformed workspace payload requests retry' "$out" '.decision == "continue"'
out=$(printf 'invalid' | "$ADAPTER" codex)
check 'Malformed JSON does not become success' "$out" '.decision == "block"'
printf '%s/%s passed\n' "$PASS" "$((PASS + FAIL))"
test "$FAIL" -eq 0
