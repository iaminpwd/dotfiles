#!/usr/bin/env python3
"""qnotch-bridge.py - WSL의 Claude Code 훅 이벤트를 Windows의 QNotch로 전달한다.

bin/hooks/qnotch-bridge-hook.sh 가 WSL에서만 python3 -I 로 실행한다.

QNotch는 Windows 쪽 Claude 설정(%USERPROFILE%\\.claude\\settings.json)에만
"QNotch.exe agent" 훅을 등록하므로 WSL에서 도는 Claude Code 세션은 보이지 않는다.
이 브리지가 Windows 설정에 등록된 같은 명령을 찾아 WSL interop으로 호출한다.
exe 위치를 Windows 설정에서 매번 읽으므로 QNotch를 옮겨도 따라간다.

- Windows 프로그램이 읽을 수 있도록 cwd/transcript_path 를 Windows 경로로 바꾼다.
- QNotch는 SessionStart 를 받은 세션만 인식하므로, 훅 등록 전에 시작된 세션은
  처음 보는 시점에 SessionStart 를 먼저 보낸다.
- 백그라운드 서브에이전트가 도는 동안 메인 턴이 끝나면 Stop 이 먼저 나가 작업 중에
  '완료'로 보이고, 서브에이전트 완료 알림으로 메인이 재개돼도 UserPromptSubmit 이
  없어 '완료'에 머문다. 세션별 상태로 보정한다.
  * 서브에이전트가 도는 동안 메인의 Stop 은 보내지 않는다.
  * Stop 뒤에 도구 이벤트가 오면 UserPromptSubmit 을 먼저 보내 '작업 중'으로 돌린다.

QNotch가 꺼져 있거나 어떤 오류가 나도 Claude Code 를 막지 않도록 출력 없이 0으로
끝난다. QNotch 응답은 버리므로 노치에서 권한 요청에 답하는 기능은 WSL에서 쓰지 않는다.

환경 변수(테스트용): QNOTCH_BRIDGE_DRY_RUN=1(전송 생략), QNOTCH_BRIDGE_LOG(전송한
이벤트 기록 파일), QNOTCH_BRIDGE_STATE_DIR, QNOTCH_BRIDGE_WIN_SETTINGS(Windows
settings.json 경로), QNOTCH_BRIDGE_EXE(QNotch 실행 파일 경로 직접 지정).
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import time

CMD_EXE = "/mnt/c/Windows/System32/cmd.exe"
# Windows 쪽 QNotch 훅과 같은 이벤트 (모두 "agent" 하위 명령)
QNOTCH_EVENTS = {
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "Notification", "Stop", "SessionEnd",
}
RESUME_EVENTS = {"PreToolUse", "PostToolUse"}
# 이 시간 동안 아무 이벤트도 없는 서브에이전트는 비정상 종료로 보고 무시한다.
AGENT_STALE_SECONDS = 10 * 60

STATE_DIR = os.environ.get("QNOTCH_BRIDGE_STATE_DIR",
                           os.path.expanduser("~/.cache/qnotch-bridge"))
DRY_RUN = os.environ.get("QNOTCH_BRIDGE_DRY_RUN") == "1"
LOG_PATH = os.environ.get("QNOTCH_BRIDGE_LOG")


def windows_to_wsl_path(path):
    """C:\\a\\b 또는 C:/a/b 를 /mnt/c/a/b 로 바꾼다."""
    m = re.match(r"^([A-Za-z]):[/\\]*(.*)$", path.strip())
    if not m:
        return ""
    rest = re.sub(r"[/\\]+", "/", m.group(2)).strip("/")
    return "/mnt/" + m.group(1).lower() + ("/" + rest if rest else "")


def to_windows_path(path):
    """WSL 경로를 Windows 프로그램이 읽을 수 있는 경로로 바꾼다."""
    if not isinstance(path, str) or not path.startswith("/"):
        return path
    parts = path.split("/")
    if len(parts) > 2 and parts[1] == "mnt" and len(parts[2]) == 1:
        return parts[2].upper() + ":\\" + "\\".join(parts[3:])
    distro = os.environ.get("WSL_DISTRO_NAME", "Ubuntu")
    return "\\\\wsl.localhost\\" + distro + path.replace("/", "\\")


def windows_settings_path():
    """Windows 쪽 Claude settings.json 경로. %USERPROFILE% 조회는 느리므로 캐시한다."""
    override = os.environ.get("QNOTCH_BRIDGE_WIN_SETTINGS")
    if override:
        return override
    cache = os.path.join(STATE_DIR, "windows-userprofile")
    try:
        with open(cache, encoding="utf-8") as f:
            profile = f.read().strip()
    except OSError:
        profile = ""
        if os.access(CMD_EXE, os.X_OK):
            try:
                out = subprocess.run([CMD_EXE, "/d", "/c", "echo %USERPROFILE%"],
                                     cwd="/mnt/c", capture_output=True, timeout=5)
                profile = windows_to_wsl_path(out.stdout.decode("utf-8", "replace"))
            except (OSError, subprocess.SubprocessError):
                profile = ""
        if profile:
            with open(cache, "w", encoding="utf-8") as f:
                f.write(profile + "\n")
    return os.path.join(profile, ".claude/settings.json") if profile else ""


def qnotch_exe():
    """Windows Claude 설정에 QNotch가 등록한 실행 파일 경로를 WSL 경로로 돌려준다."""
    override = os.environ.get("QNOTCH_BRIDGE_EXE")
    if override:
        return override
    try:
        with open(windows_settings_path(), encoding="utf-8") as f:
            hooks = json.load(f).get("hooks", {})
    except (OSError, ValueError, AttributeError):
        return ""
    for groups in hooks.values():
        for group in groups if isinstance(groups, list) else []:
            for hook in group.get("hooks", []) if isinstance(group, dict) else []:
                m = re.search(r"[A-Za-z]:[^\"]*?QNotch\.exe", str(hook.get("command", "")),
                              re.IGNORECASE)
                if m:
                    return windows_to_wsl_path(m.group(0))
    return ""


def send(payloads):
    """QNotch가 받는 이벤트만 순서대로 보낸다."""
    payloads = [p for p in payloads if p.get("hook_event_name") in QNOTCH_EVENTS]
    if not payloads:
        return
    exe = "" if DRY_RUN else qnotch_exe()
    for payload in payloads:
        if LOG_PATH:
            with open(LOG_PATH, "a", encoding="utf-8") as log:
                log.write(payload["hook_event_name"] + "\n")
        if DRY_RUN or not exe or not os.path.exists(exe):
            continue
        body = dict(payload)
        for key in ("cwd", "transcript_path", "agent_transcript_path"):
            if key in body:
                body[key] = to_windows_path(body[key])
        try:
            subprocess.run([exe, "agent"],
                           input=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
        except (OSError, subprocess.SubprocessError):
            pass


def synthetic(payload, event, **extra):
    base = {key: payload.get(key) for key in ("session_id", "transcript_path", "cwd")}
    return dict(base, hook_event_name=event, **extra)


def main():
    payload = json.loads(sys.stdin.buffer.read() or b"{}")
    event = payload.get("hook_event_name", "")
    session = "".join(c for c in str(payload.get("session_id", "")) if c.isalnum() or c in "-_")
    if not session:
        send([payload])
        return

    os.makedirs(STATE_DIR, exist_ok=True)
    state_path = os.path.join(STATE_DIR, session + ".json")
    with open(state_path + ".lock", "w", encoding="utf-8") as lock:
        # 병렬 도구 호출이나 서브에이전트 훅이 동시에 상태를 고치지 않도록 잠근다.
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(state_path, encoding="utf-8") as f:
                state = json.load(f)
        except (OSError, ValueError):
            state = {}
        stopped = bool(state.get("stopped"))
        started = bool(state.get("started"))
        now = time.time()
        agents = {k: v for k, v in state.get("agents", {}).items()
                  if now - v < AGENT_STALE_SECONDS}
        agent_id = payload.get("agent_id")
        if agent_id and event != "SubagentStop":
            agents[agent_id] = now

        outgoing = []
        if event == "SessionStart":
            started = True
        elif not started and event != "SessionEnd":
            outgoing.append(synthetic(payload, "SessionStart", source="resume"))
            started = True

        if event == "SubagentStart":
            pass  # QNotch는 이 이벤트를 쓰지 않는다. 상태만 기록한다.
        elif event == "SubagentStop":
            agents.pop(agent_id, None)
        elif event == "Stop":
            if not agents:
                outgoing.append(payload)
                stopped = True
        elif event == "UserPromptSubmit":
            outgoing.append(payload)
            stopped = False
        else:
            if stopped and event in RESUME_EVENTS:
                outgoing.append(synthetic(payload, "UserPromptSubmit", prompt=""))
                stopped = False
            outgoing.append(payload)

        if event == "SessionEnd":
            for path in (state_path, state_path + ".lock"):
                try:
                    os.remove(path)
                except OSError:
                    pass
        else:
            with open(state_path, "w", encoding="utf-8") as f:
                json.dump({"stopped": stopped, "started": started, "agents": agents}, f)

    send(outgoing)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - 훅은 어떤 경우에도 에이전트를 막지 않는다.
        pass
    sys.exit(0)
