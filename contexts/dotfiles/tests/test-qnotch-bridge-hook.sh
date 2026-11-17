#!/usr/bin/env bash
# test-qnotch-bridge-hook.sh
#
# qnotch-bridge-hook.sh / qnotch-bridge.py 는 WSL의 Claude Code 훅 이벤트를 Windows
# QNotch 로 전달하면서 세션별 상태로 이벤트를 보정한다. 보정이 깨지면 노치가 작업 중에
# '완료'로 보이거나(백그라운드 서브에이전트), 훅 등록 전에 열린 세션이 아예 안 보인다.
# 실제 QNotch 대신 가짜 실행 파일과 dry-run 기록으로 전달 순서·인자·경로 변환을 검증하고,
# 비WSL·오류 상황에서 훅이 출력 없이 0으로 끝나는지(에이전트를 막지 않는지) 확인한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-qnotch-bridge-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/bin/hooks/qnotch-bridge-hook.sh"
BRIDGE_PY="$REPO_ROOT/bin/hooks/qnotch-bridge.py"

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

PYTHON=/usr/bin/python3
[ -x "$PYTHON" ] || PYTHON=$(command -v python3 2>/dev/null) || PYTHON=""
if [ -z "$PYTHON" ]; then
  echo "[WARNING] SKIP test-qnotch-bridge-hook: python3 이 없어 브리지 동작을 검증하지 못했습니다."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export QNOTCH_BRIDGE_STATE_DIR="$TMP/state"
export WSL_DISTRO_NAME=TestDistro

echo "=== qnotch-bridge-hook.sh 전달·상태 보정 회귀 테스트 ==="

# 1. WSL 이 아니면 아무것도 하지 않는다.
rc=0
out=$(printf '%s' '{"session_id":"s","hook_event_name":"Stop"}' | DOTFILES_FORCE_WSL=0 bash "$HOOK") || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -e "$QNOTCH_BRIDGE_STATE_DIR" ]; then
  report "비WSL 은 출력·상태 없이 종료" 0
else
  report "비WSL 은 출력·상태 없이 종료" 1 "rc=$rc out=$out"
fi

# 2. 시나리오별 전달 순서 (dry-run 기록)
export DOTFILES_FORCE_WSL=1
ev() { printf '{"session_id":"%s","hook_event_name":"%s"%s}' "$1" "$2" "${3:-}" | QNOTCH_BRIDGE_DRY_RUN=1 bash "$HOOK"; }
run_case() { # 이름, 기대 순서, 시나리오 함수
  local name=$1 expect=$2 fn=$3 got
  export QNOTCH_BRIDGE_LOG="$TMP/$name.log"
  "$fn" "sid-$name"
  got=$(paste -sd, "$QNOTCH_BRIDGE_LOG" 2>/dev/null || true)
  unset QNOTCH_BRIDGE_LOG
  if [ "$got" = "$expect" ]; then
    report "$name" 0
  else
    report "$name" 1 "기대 $expect / 실제 $got"
  fi
}
s_plain() {
  ev "$1" UserPromptSubmit
  ev "$1" PreToolUse
  ev "$1" PostToolUse
  ev "$1" Stop
}
s_background() {
  ev "$1" UserPromptSubmit
  ev "$1" SubagentStart ',"agent_id":"a1"'
  ev "$1" Stop
  ev "$1" PreToolUse ',"agent_id":"a1"'
  ev "$1" SubagentStop ',"agent_id":"a1"'
  ev "$1" PreToolUse
  ev "$1" Stop
}
s_resume() {
  ev "$1" UserPromptSubmit
  ev "$1" Stop
  ev "$1" PreToolUse
  ev "$1" Stop
}
s_idle() {
  ev "$1" UserPromptSubmit
  ev "$1" Stop
  ev "$1" Notification
}
s_session() {
  ev "$1" SessionStart
  ev "$1" UserPromptSubmit
  ev "$1" Stop
  ev "$1" SessionEnd
}
run_case "처음 보는 세션은 SessionStart 를 먼저 보냄" \
  "SessionStart,UserPromptSubmit,PreToolUse,PostToolUse,Stop" s_plain
run_case "서브에이전트 실행 중 메인 Stop 은 보류" \
  "SessionStart,UserPromptSubmit,PreToolUse,PreToolUse,Stop" s_background
run_case "Stop 뒤 도구 이벤트는 작업 재개로 보정" \
  "SessionStart,UserPromptSubmit,Stop,UserPromptSubmit,PreToolUse,Stop" s_resume
run_case "입력 대기 알림은 재개로 보지 않음" \
  "SessionStart,UserPromptSubmit,Stop,Notification" s_idle
run_case "SessionStart 로 시작한 세션은 중복 없이 전달" \
  "SessionStart,UserPromptSubmit,Stop,SessionEnd" s_session

# 3. 실제 전달: 가짜 QNotch 로 인자와 Windows 경로 변환을 확인한다.
FAKE="$TMP/fake-qnotch"
cat >"$FAKE" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMP/fake.args"
cat >>"$TMP/fake.stdin"
printf '\n' >>"$TMP/fake.stdin"
STUB
chmod +x "$FAKE"
# 링크 줄은 powershell.exe 가 QNotch 파이프에 쓴다. 가짜는 -EncodedCommand 값을 기록한다.
FAKE_PS="$TMP/fake-powershell"
cat >"$FAKE_PS" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\${@: -1}" >>"$TMP/fake-ps.args"
STUB
chmod +x "$FAKE_PS"
export QNOTCH_BRIDGE_POWERSHELL="$FAKE_PS"
rc=0
out=$(printf '%s' '{"session_id":"real","hook_event_name":"UserPromptSubmit","cwd":"/home/u/proj","transcript_path":"/mnt/c/Users/u/t.jsonl"}' |
  CLAUDE_CODE_ENTRYPOINT=claude-desktop CLAUDE_CODE_HOST_SESSION_ID=local_abc-1 \
    QNOTCH_BRIDGE_EXE="$FAKE" bash "$HOOK") || rc=$?
# 링크 줄은 기다리지 않고 띄우므로 기록될 때까지 잠시 기다린다.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$TMP/fake-ps.args" ] && break
  sleep 0.2
done
# 같은 세션의 도구 이벤트는 링크를 다시 보내지 않고, 데스크톱 앱 세션이 아니거나
# 세션 ID 형식이 다르면 링크를 보내지 않는다.
printf '%s' '{"session_id":"real","hook_event_name":"PreToolUse","tool_name":"Bash"}' |
  CLAUDE_CODE_ENTRYPOINT=claude-desktop CLAUDE_CODE_HOST_SESSION_ID=local_abc-1 \
    QNOTCH_BRIDGE_EXE="$FAKE" bash "$HOOK"
printf '%s' '{"session_id":"cli","hook_event_name":"UserPromptSubmit"}' |
  CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CODE_HOST_SESSION_ID=local_abc-1 QNOTCH_BRIDGE_EXE="$FAKE" bash "$HOOK"
printf '%s' '{"session_id":"bad","hook_event_name":"UserPromptSubmit"}' |
  CLAUDE_CODE_ENTRYPOINT=claude-desktop CLAUDE_CODE_HOST_SESSION_ID='local_a&b' QNOTCH_BRIDGE_EXE="$FAKE" bash "$HOOK"
sleep 0.5
if "$PYTHON" -I -c '
import base64, sys
rows = [base64.b64decode(l).decode("utf-16-le") for l in open(sys.argv[1]) if l.strip()]
assert len(rows) == 1, rows
s = rows[0]
assert "\"session\":\"real\"" in s and "\"event\":\"Link\"" in s, s
assert "\"link\":\"claude://code/continue?session=local_abc-1\"" in s, s
assert "QNotch.Agents" in s, s
' "$TMP/fake-ps.args" 2>"$TMP/link.err"; then
  report "데스크톱 앱 WSL 세션만 QNotch 파이프에 세션 링크 1회 전달" 0
else
  report "데스크톱 앱 WSL 세션만 QNotch 파이프에 세션 링크 1회 전달" 1 "$(cat "$TMP/link.err")"
fi
if [ "$rc" -eq 0 ] && [ -z "$out" ] &&
  [ "$(head -2 "$TMP/fake.args" | paste -sd,)" = "agent,agent" ] &&
  "$PYTHON" -I -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()][:2]
assert [r["hook_event_name"] for r in rows] == ["SessionStart", "UserPromptSubmit"], rows
assert rows[1]["cwd"] == "\\\\wsl.localhost\\TestDistro\\home\\u\\proj", rows[1]["cwd"]
assert rows[1]["transcript_path"] == "C:\\Users\\u\\t.jsonl", rows[1]["transcript_path"]
' "$TMP/fake.stdin"; then
  report "가짜 QNotch 에 agent 인자·Windows 경로로 전달" 0
else
  report "가짜 QNotch 에 agent 인자·Windows 경로로 전달" 1 "rc=$rc args=$(cat "$TMP/fake.args" 2>/dev/null) stdin=$(cat "$TMP/fake.stdin" 2>/dev/null)"
fi

# 4. Windows Claude 설정에 QNotch 가 등록한 명령에서 exe 위치를 찾는다.
WIN_SETTINGS="$TMP/win-settings.json"
printf '%s' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"C:/Users/u/Apps/QNotch.exe\" agent"}]}]}}' >"$WIN_SETTINGS"
found=$(QNOTCH_BRIDGE_WIN_SETTINGS="$WIN_SETTINGS" "$PYTHON" -I -B -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("qnotch_bridge", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.qnotch_exe())
' "$BRIDGE_PY")
if [ "$found" = "/mnt/c/Users/u/Apps/QNotch.exe" ]; then
  report "Windows 설정의 QNotch 명령에서 exe 경로 해석" 0
else
  report "Windows 설정의 QNotch 명령에서 exe 경로 해석" 1 "실제 $found"
fi

# 5. QNotch 가 실패하거나 입력이 깨져도 훅은 출력 없이 0으로 끝난다.
printf '#!/usr/bin/env bash\nexit 3\n' >"$TMP/failing-qnotch"
chmod +x "$TMP/failing-qnotch"
rc1=0 rc2=0
out1=$(printf '%s' '{"session_id":"f","hook_event_name":"Stop"}' | QNOTCH_BRIDGE_EXE="$TMP/failing-qnotch" bash "$HOOK") || rc1=$?
out2=$(printf '%s' '{not json' | bash "$HOOK") || rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -z "$out1$out2" ]; then
  report "QNotch 실패·깨진 입력에도 에이전트를 막지 않음" 0
else
  report "QNotch 실패·깨진 입력에도 에이전트를 막지 않음" 1 "rc1=$rc1 rc2=$rc2 out=$out1$out2"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
