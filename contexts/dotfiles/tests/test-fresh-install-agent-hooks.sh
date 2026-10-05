#!/usr/bin/env bash
# fresh macOS처럼 빈 HOME + BSD readlink 환경에서도 최초 에이전트 훅 등록이 성립하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo '[WARNING] SKIP: jq 필요 (fresh agent-hook bootstrap 회귀)'
  exit 0
fi

mkdir -p "$TMP/home" "$TMP/work" "$TMP/fakebin"

# macOS 기본 BSD readlink처럼 -f 옵션만 지원하지 않도록 모사한다.
cat >"$TMP/fakebin/readlink" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-f" ]; then
  echo 'readlink: illegal option -- f' >&2
  exit 1
fi
exec /usr/bin/readlink "$@"
STUB
chmod +x "$TMP/fakebin/readlink"

status=0
(
  cd "$TMP/work"
  HOME="$TMP/home" PATH="$TMP/fakebin:$PATH" \
    bash "$ROOT/bin/utils/merge-agent-hooks.sh" "$ROOT/ansible"
) >"$TMP/out" 2>&1 || status=$?

if [ "$status" -ne 0 ]; then
  cat "$TMP/out"
  echo 'FAIL: 빈 HOME의 fresh install에서 BSD readlink 환경이 최초 에이전트 훅 등록을 막았습니다.'
  exit 1
fi

CLAUDE="$TMP/home/.claude/settings.json"
GEMINI="$TMP/home/.gemini/config/hooks.json"

jq -e '
  [.hooks.PostToolUse[].hooks[].command] | any(endswith("agent-edits-hook.sh"))
' "$CLAUDE" >/dev/null
jq -e '
  [.hooks.Stop[].hooks[].command] | any(endswith("pre-flight-gate-hook.sh"))
' "$CLAUDE" >/dev/null
jq -e '
  [."agent-edits-log".PostToolUse[].hooks[].command] | any(endswith("agent-edits-hook.sh"))
' "$GEMINI" >/dev/null

echo 'PASS: 빈 HOME + BSD readlink에서도 최초 에이전트 훅 등록 완료'
