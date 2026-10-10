#!/usr/bin/env bash
# Adapt Codex / Antigravity Stop payloads to the unchanged Claude Stop gate.
set -uo pipefail

CLIENT=${1:-}
case "$CLIENT" in codex | antigravity) ;; *)
  echo '[ERROR] expected codex or antigravity' >&2
  exit 2
  ;;
esac
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
# shellcheck disable=SC1091
source "$HERE/../lib/jq-resolve.sh"
JQ=$(resolve_jq)
if [ -z "$JQ" ] || ! "$JQ" --version >/dev/null 2>&1; then
  echo '[ERROR] jq is required to adapt Stop responses' >&2
  exit 2
fi

payload=$(cat)
reason=''
if ! "$JQ" -e 'type == "object"' <<<"$payload" >/dev/null 2>&1; then
  reason='Invalid Stop payload: expected JSON object.'
fi
reasons=()
check_root() {
  local root=$1 engine_out rc=0 why diagnostics
  # Leave scope, policy, success caching, warnings and fingerprinting to the
  # original validator. The adapter never marks a failed check as a pass.
  # shellcheck disable=SC2016
  engine_out=$(printf '%s\n' "$("$JQ" -n --arg cwd "$root" '{cwd:$cwd,stop_hook_active:false}')" | "$HERE/pre-flight-gate-hook.sh") || rc=$?
  if [ "$rc" -ne 0 ]; then
    reasons+=("Stop verification failed to execute for $root (exit $rc).")
  elif [ -n "$engine_out" ]; then
    if ! "$JQ" -e 'type == "object"' <<<"$engine_out" >/dev/null 2>&1; then
      reasons+=("Stop verification returned invalid JSON for $root.")
    elif [ "$("$JQ" -r '.decision // ""' <<<"$engine_out")" = block ]; then
      why=$("$JQ" -r '.reason // "Stop verification failed"' <<<"$engine_out")
      diagnostics=$("$JQ" -r '.hookSpecificOutput.additionalContext // ""' <<<"$engine_out")
      reasons+=("$root: $why"$'\n'"$diagnostics")
    fi
  fi
}

if [ -z "$reason" ]; then
  if [ "$CLIENT" = codex ]; then
    if [ "$("$JQ" -r '.stop_hook_active // false' <<<"$payload")" != true ]; then
      cwd=$("$JQ" -r '.cwd // empty' <<<"$payload")
      if [ -z "$cwd" ]; then
        reason='Codex Stop input has no cwd; verification could not run.'
      else
        check_root "$cwd"
      fi
    fi
  else
    # Antigravity may terminate while background tasks are still running.
    if [ "$("$JQ" -r '.fullyIdle // false' <<<"$payload")" != true ]; then
      reason='Background tasks are still active; finish them before Stop verification.'
    else
      count=0
      while IFS= read -r -d '' workspace; do
        count=$((count + 1))
        check_root "$workspace"
      done < <("$JQ" -rj '.workspacePaths[]? | select(type=="string" and length>0) | . + "\u0000"' <<<"$payload")
      [ "$count" -gt 0 ] || reason='Antigravity Stop input has no workspacePaths.'
    fi
  fi
fi
if [ "${#reasons[@]}" -gt 0 ]; then
  printf -v joined '%s\n' "${reasons[@]}"
  reason="${reason:+$reason$'\n'}$joined"
fi
if [ "$CLIENT" = antigravity ]; then
  if [ -n "$reason" ]; then
    # executionNum is the *execution attempt index*, NOT a documented
    # Stop-retry counter. Do not silently accept failures based on its value.
    # Unrecoverable runtime termination cannot re-enter the model loop.
    termination=$("$JQ" -r '.terminationReason // "model_stop"' <<<"$payload" 2>/dev/null)
    if [ "$termination" = model_stop ]; then
      # shellcheck disable=SC2016
      "$JQ" -n --arg reason "$reason" '{decision:"continue",reason:$reason}'
    else
      echo "[WARNING] Antigravity terminated ($termination) before Stop verification passed: $reason" >&2
      printf '{"decision":"allow"}\n'
    fi
  else
    printf '{"decision":"allow"}\n'
  fi
else
  if [ -n "$reason" ]; then
    # shellcheck disable=SC2016
    "$JQ" -n --arg reason "$reason" '{decision:"block",reason:$reason}'
  else
    printf '{}\n'
  fi
fi
