#!/usr/bin/env bash
# 스킬 라우팅 실측기 — cases.tsv 를 헤드리스로 반복 실행해 observed.tsv 를 생성한다.
#
# IDE 확장 번들(Antigravity/VS Code) 바이너리 자동 탐색 (별도 CLI 설치 불필요)
#
# 관측 방식: 도구를 Skill로 한정해 호출 내역(tool_use) 추출. 중립 디렉토리 실행으로 기본 룰 로드 방지.
#
# --max-turns 1: 라우팅 판단(첫 턴)만 수행하여 케이스당 실행 시간 최소화 (약 17초)
#
# 반복 측정: 라우팅 비결정성(노이즈) 극복. pass^k(전회 성공) 기준 집계 및 다수결 결과 기록.
#
# [비용 주의] 실제 세션 실행으로 토큰 소모 큼. (run.sh 로컬 분석 먼저 -> 부분 측정 -> 전체 갱신)
# [실행 가드] 과도한 비용 방지를 위해 세션 수 상한 검사 및 사용자 명시적 승인 요구
#
# 사용: bash ~/dotfiles/contexts/prompt-architect/evals/routing/measure.sh [케이스ID ...]
#       인자를 주면 해당 케이스만, 없으면 전체를 측정한다.
#       ROUTING_REPEATS(기본 3) 반복 횟수, ROUTING_JOBS(기본 4) 동시 실행 수,
#       ROUTING_TIMEOUT(기본 120) 케이스 1회당 한정시간,
#       ROUTING_MAX_SESSIONS(기본 30) 세션 수 상한,
#       ROUTING_MEASURE_CONFIRM=yes 비대화형 실행 승인.

set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES="$EVAL_DIR/cases.tsv"
OBSERVED="$EVAL_DIR/observed.tsv"
RUNS_FILE="$EVAL_DIR/observed-runs.tsv"
TIMEOUT_SEC="${ROUTING_TIMEOUT:-120}"
JOBS="${ROUTING_JOBS:-4}"
REPEATS="${ROUTING_REPEATS:-3}"

[ -f "$CASES" ] || {
  echo "[ERROR] 케이스 파일이 없습니다: $CASES" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# CLI 탐색: PATH 우선, 없으면 IDE 확장 번들 바이너리
# -----------------------------------------------------------------------------
find_cli() {
  local c
  if c=$(command -v claude 2>/dev/null) && "$c" --version >/dev/null 2>&1; then
    echo "$c"
    return 0
  fi
  # 확장은 버전마다 디렉토리명이 바뀌므로 glob 후 최신 버전을 고른다.
  shopt -s nullglob
  local candidates=(
    "$HOME"/.antigravity-ide-server/extensions/anthropic.claude-code-*/resources/native-binary/claude
    "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude
    "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude
    "$HOME"/.cursor-server/extensions/anthropic.claude-code-*/resources/native-binary/claude
  )
  shopt -u nullglob
  local best=""
  for c in "${candidates[@]}"; do
    [ -x "$c" ] || continue
    best="$c"
  done
  [ -n "$best" ] || return 1
  echo "$best"
}

CLI=$(find_cli) || {
  echo "[ERROR] Claude Code 실행 파일을 찾지 못했습니다." >&2
  echo "        PATH 의 'claude' 또는 IDE 확장 번들 바이너리가 필요합니다." >&2
  exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# stream-json 에서 Skill 호출만 추출하는 파서 (병렬 잡마다 독립 실행)
PARSER="$WORK/parse.py"
cat >"$PARSER" <<'PY'
import json, sys
called = []
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get('type') != 'assistant':
        continue
    for c in d.get('message', {}).get('content', []):
        if c.get('type') == 'tool_use' and c.get('name') == 'Skill':
            s = (c.get('input') or {}).get('skill')
            if s and s not in called:
                called.append(s)
print(','.join(called) if called else 'none')
PY

# 로드 순서 무관 집합 비교 (오탐 방지)
canon() { tr ',' '\n' <<<"$1" | sort -u | paste -sd, -; }

# -----------------------------------------------------------------------------
# 한 케이스를 REPEATS 회 실행 → 다수결 결과와 회차별 원본을 기록
# 병렬 실행되므로 케이스별로 독립된 임시 파일과 작업 디렉토리를 쓴다.
# -----------------------------------------------------------------------------
observe_one() {
  local cid=$1 expected=$2 input=$3
  local dir="$WORK/c.$cid" raw="$WORK/raw.$cid" got i hits=0 want
  want=$(canon "$expected")
  mkdir -p "$dir"
  : >"$WORK/runs.$cid"

  for ((i = 1; i <= REPEATS; i++)); do
    (
      cd "$dir" || exit 1
      local prompt="사용자 요청을 해결하기 위해 필요한 모든 'Skill' 도구를 판단하여 호출하십시오. 둘 이상의 도메인이 섞인 복합 요청이라면, 관련된 모든 스킬을 반드시 한 턴에 동시에(Multi-tool call) 호출해야 합니다. 요청: $input"
      timeout "$TIMEOUT_SEC" "$CLI" -p "$prompt" \
        --output-format stream-json --verbose \
        --allowed-tools Skill \
        --disallowed-tools Bash Read Glob Grep Write Edit NotebookEdit WebFetch WebSearch Task \
        --max-turns 1 </dev/null
    ) >"$raw" 2>/dev/null || true
    got=$(python3 "$PARSER" "$raw" 2>/dev/null || echo none)
    # idempotency:bypass (임시 파일에 대한 단순 반복 기록)
    printf '%s\t%s\t%s\n' "$cid" "$i" "$got" >>"$WORK/runs.$cid"
    [ "$(canon "$got")" = "$want" ] && hits=$((hits + 1))
  done

  # 다수결(최빈값). 반드시 canon 으로 정규화한 값 위에서 센다.
  # 스킬 로드 "순서"는 라우팅 판정과 무관해서 이 스크립트는 이미 canon() 으로 순서를
  # 지운 뒤 hits 를 세는데, 정작 다수결만 원문 문자열로 투표하고 있었다. 그러면 같은
  # 집합이 순서만 달라 표가 쪼개진다(실측: k8s,aws / aws,k8s / k8s,aws -> 집합 기준이면
  # 3표 만장일치인데 원문 기준으로는 2표). 그 결과가 observed.tsv 에 기록되고 run.sh 의
  # 채점 대상이 되므로, 안정성 통계(hits)와 기록값이 서로 다른 기준을 쓰게 된다.
  # 동률 처리도 함께 바로잡아 적는다: sort|uniq -c|sort -k1,1nr 는 GNU sort 의 최후 비교가
  # 줄 전체를 보므로 "먼저 관측된 것"이 아니라 사전순으로 갈린다(실측). canon 이 이미
  # 값을 정렬해 두므로 동률 시 선택은 사전순으로 결정적이며, 그 사실을 그대로 적는다.
  local majority
  majority=$(cut -f3 "$WORK/runs.$cid" | while IFS= read -r line; do canon "$line"; done |
    sort | uniq -c | sort -k1,1nr | head -1 | sed 's/^ *[0-9]* //')
  printf '%s\t%s\n' "$cid" "$majority" >"$WORK/res.$cid"
  printf '%s\t%s\t%s\n' "$cid" "$hits" "$REPEATS" >"$WORK/stat.$cid"

  if [ "$hits" -eq "$REPEATS" ]; then
    printf '  %-5s 기대[%s] 실제[%s]  %s/%s 안정\n' "$cid" "$expected" "$majority" "$hits" "$REPEATS"
  elif [ "$hits" -eq 0 ]; then
    printf '  %-5s 기대[%s] 실제[%s]  %s/%s 전회 불일치\n' "$cid" "$expected" "$majority" "$hits" "$REPEATS"
  else
    printf '  %-5s 기대[%s] 실제[%s]  %s/%s 불안정\n' "$cid" "$expected" "$majority" "$hits" "$REPEATS"
  fi
}

# -----------------------------------------------------------------------------
# 메인: 케이스 수집 후 JOBS 개씩 병렬 실행
# -----------------------------------------------------------------------------
declare -A WANTED=()
if [ "$#" -gt 0 ]; then
  for id in "$@"; do WANTED["$id"]=1; done
fi

ids=()
declare -A EXP=() INP=()
while IFS=$'\t' read -r cid expected input; do
  case "$cid" in '#'* | '') continue ;; esac
  [ -n "${input:-}" ] || continue
  if [ "${#WANTED[@]}" -gt 0 ] && [ -z "${WANTED[$cid]:-}" ]; then continue; fi
  ids+=("$cid")
  EXP["$cid"]=$expected
  INP["$cid"]=$input
done <"$CASES"

if [ "${#ids[@]}" -eq 0 ]; then
  echo "[ERROR] 측정한 케이스가 없습니다." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 실행 비용 가드
# -----------------------------------------------------------------------------
# 이 스크립트는 케이스 1회당 실제 에이전트 세션을 띄우므로 토큰이 빠르게 소모된다.
# 사고를 막기 위해 두 겹으로 제어한다.
#   1) 세션 수 상한: 기본 30개를 넘으면 거부하고, 올리려면 ROUTING_MAX_SESSIONS 를 명시해야 한다.
#   2) 실행 승인: 대화형 터미널이면 직접 묻고, 비대화형(에이전트 도구 호출, CI, 훅)이면
#      ROUTING_MEASURE_CONFIRM=yes 가 없는 한 무조건 거부한다. 에이전트 실행에는 TTY 가
#      없으므로 이 조건 하나로 "에이전트가 무심코 돌리는" 경로가 막힌다.
PLANNED=$((${#ids[@]} * REPEATS))
MAX_SESSIONS="${ROUTING_MAX_SESSIONS:-30}"

echo "[COST] 예정 세션 수: ${#ids[@]}건 x ${REPEATS}회 = ${PLANNED}개 (에이전트 세션 1개당 토큰 소모)"

if [ "$PLANNED" -gt "$MAX_SESSIONS" ]; then
  echo "[BLOCKED] 예정 세션 ${PLANNED}개가 상한 ${MAX_SESSIONS}개를 초과해 실행을 중단합니다." >&2
  echo "          비용을 줄이려면 케이스 ID 를 인자로 지정해 부분 측정하십시오." >&2
  echo "            예) bash ${BASH_SOURCE[0]} M02 M03 M04" >&2
  echo "          반복 횟수를 줄이려면 ROUTING_REPEATS=1 을 쓰십시오." >&2
  echo "          상한을 알고도 올리려면 ROUTING_MAX_SESSIONS=${PLANNED} 을 명시하십시오." >&2
  exit 3
fi

if [ "${ROUTING_MEASURE_CONFIRM:-}" != "yes" ]; then
  if [ -t 0 ]; then
    printf '[CONFIRM] 세션 %d개를 실행합니다. 진행하려면 yes 를 입력하십시오: ' "$PLANNED"
    read -r answer
    if [ "$answer" != "yes" ]; then
      echo "[BLOCKED] 사용자가 승인하지 않아 실행하지 않았습니다." >&2
      exit 3
    fi
  else
    echo "[BLOCKED] 비대화형 실행은 기본 중단됩니다(에이전트 도구 호출, CI, 훅 등)." >&2
    echo "          토큰이 소모되는 작업이므로 사용자의 명시적 승인이 필요합니다." >&2
    echo "          의도한 실행이라면 ROUTING_MEASURE_CONFIRM=yes 를 붙이십시오." >&2
    echo "            예) ROUTING_MEASURE_CONFIRM=yes bash ${BASH_SOURCE[0]} M02 M03" >&2
    exit 3
  fi
fi

echo "[INFO] 실행 파일: $CLI"
echo "[INFO] 케이스 ${#ids[@]}건 x ${REPEATS}회 = ${PLANNED}회 실행, 동시 ${JOBS}개, 1회당 한정 ${TIMEOUT_SEC}초"

running=0
for cid in "${ids[@]}"; do
  observe_one "$cid" "${EXP[$cid]}" "${INP[$cid]}" &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then
    wait -n
    running=$((running - 1))
  fi
done
wait

# cases.tsv 순서대로 취합
TMP_OUT="$WORK/observed.partial"
TMP_RUNS="$WORK/runs.partial"
: >"$TMP_OUT"
: >"$TMP_RUNS"
stable=0
for cid in "${ids[@]}"; do
  [ -f "$WORK/res.$cid" ] && cat "$WORK/res.$cid" >>"$TMP_OUT"
  [ -f "$WORK/runs.$cid" ] && cat "$WORK/runs.$cid" >>"$TMP_RUNS"
  if [ -f "$WORK/stat.$cid" ]; then
    h=$(cut -f2 "$WORK/stat.$cid")
    [ "$h" -eq "$REPEATS" ] && stable=$((stable + 1))
  fi
done

# 부분 측정(인자 지정)일 때 기존 결과를 덮어쓰지 않고 병합한다.
merge_into() {
  local new=$1 dest=$2
  if [ "${#WANTED[@]}" -gt 0 ] && [ -f "$dest" ]; then
    awk -F'\t' 'NR==FNR{seen[$1]=1;next} !($1 in seen)' "$new" "$dest" >"$WORK/keep" || true
    cat "$WORK/keep" "$new" | sort >"$dest"
  else
    sort "$new" >"$dest"
  fi
}
merge_into "$TMP_OUT" "$OBSERVED"
merge_into "$TMP_RUNS" "$RUNS_FILE"

echo
echo "[INFO] pass^${REPEATS} (${REPEATS}회 전부 기대와 일치): ${stable}/${#ids[@]}"
echo "[INFO] 다수결 결과 -> $OBSERVED"
echo "[INFO] 회차별 원본 -> $RUNS_FILE"
echo "[INFO] 채점: bash $EVAL_DIR/run.sh"
