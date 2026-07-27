#!/usr/bin/env bash
# 스킬 라우팅 실측기 — cases.tsv 를 헤드리스로 반복 실행해 observed.tsv 를 생성한다.
#
# 별도 CLI 설치는 필요 없다. Claude Code IDE 확장(Antigravity/VS Code)이 네이티브
# 바이너리를 번들하므로 그것을 자동 탐색해 쓴다(2026-07-27 확인:
# ~/.antigravity-ide-server/extensions/anthropic.claude-code-*/resources/native-binary/claude).
#
# 관측 방식: 도구를 Skill 하나로 제한해 실행하면, 에이전트가 파일을 뒤지는 대신
# 라우팅 판단만 수행하므로 stream-json 의 tool_use(name=Skill) 가 곧 "로드된 스킬"이다.
# 중립 디렉토리에서 실행해 dotfiles 의 CLAUDE.md 가 자동 로드되지 않게 한다
# (dotfiles 스킬은 description 라우팅 대상이 아니므로 cases.tsv 에서도 제외되어 있다).
#
# --max-turns 1 인 이유: 필요한 것은 첫 턴의 라우팅 판단뿐이다. 턴을 더 주면 스킬을
# 로드한 뒤 실제 답변까지 생성해 케이스당 3분이 걸린다(2026-07-27 실측: turns=4 약 180초,
# turns=1 약 17초, 라우팅 결과는 동일).
#
# 반복 측정이 기본인 이유: 라우팅은 비결정적이다. 같은 입력에 S01 이 [aws] 와
# [aws,pre-flight-check] 로, M04 가 [observability,k8s] 와 [observability] 로 갈렸다
# (2026-07-27 실측). 1회 draw 로는 description 수정이 개선인지 노이즈인지 구분할 수 없다.
# 필요한 스킬은 "매번" 떠야 하므로 집계는 pass@k(1회라도 성공)가 아니라 pass^k(k회 전부
# 성공) 기준으로 본다. observed.tsv 에는 채점기 호환을 위해 다수결 결과를 기록하고,
# 회차별 원본은 observed-runs.tsv 에 남겨 분산을 추적한다.
#
# [비용 주의] 이 스크립트는 케이스 1회당 실제 에이전트 세션을 1개 띄운다. 전체 측정은
# 36건 x REPEATS 회이므로 기본값 기준 108개 세션이 뜨고 토큰이 그만큼 소모된다
# (2026-07-27 실측: 1회 전체 측정으로 세션 토큰 예산의 상당 부분을 소진). description 을
# 고칠 때마다 습관적으로 돌리지 말고, 아래 순서로 비용을 통제하십시오.
#   1. 로컬 무료 검사 먼저: run.sh 의 description 용어 중복 분석은 API 호출이 없다.
#   2. 부분 측정: 고친 스킬과 관련된 케이스 ID 만 인자로 지정한다.
#   3. 전체 재측정: 베이스라인을 갱신할 때만 수행한다.
#
# [실행 가드] 위 비용 때문에 기본적으로 막혀 있다. 아래 두 조건을 모두 통과해야 실행된다.
#   - 세션 수 상한: 예정 세션이 ROUTING_MAX_SESSIONS(기본 30)를 넘으면 거부한다.
#   - 실행 승인: 대화형 터미널이면 yes 입력을 묻고, 비대화형이면 ROUTING_MEASURE_CONFIRM=yes
#     가 없는 한 거부한다. 차단 시 종료 코드는 3 이다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/evals/routing/measure.sh [케이스ID ...]
#       인자를 주면 해당 케이스만, 없으면 전체를 측정한다.
#       ROUTING_REPEATS(기본 3) 반복 횟수, ROUTING_JOBS(기본 4) 동시 실행 수,
#       ROUTING_TIMEOUT(기본 120) 케이스 1회당 제한시간,
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

# 로드 순서는 라우팅 정확도와 무관하므로 비교는 항상 집합으로 한다. 문자열로 비교하면
# 기대[k8s,observability] 대 실제[observability,k8s] 가 불일치로 잡힌다(run.sh 도 집합 비교).
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
      timeout "$TIMEOUT_SEC" "$CLI" -p "$input" \
        --output-format stream-json --verbose \
        --allowed-tools Skill \
        --disallowed-tools Bash Read Glob Grep Write Edit NotebookEdit WebFetch WebSearch Task \
        --max-turns 1 </dev/null
    ) >"$raw" 2>/dev/null || true
    got=$(python3 "$PARSER" "$raw" 2>/dev/null || echo none)
    printf '%s\t%s\t%s\n' "$cid" "$i" "$got" >>"$WORK/runs.$cid"
    [ "$(canon "$got")" = "$want" ] && hits=$((hits + 1))
  done

  # 다수결(최빈값). 동률이면 먼저 관측된 것을 택한다.
  local majority
  majority=$(cut -f3 "$WORK/runs.$cid" | sort | uniq -c | sort -k1,1nr | head -1 | sed 's/^ *[0-9]* //')
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
# 이 스크립트는 케이스 1회당 실제 에이전트 세션을 띄우므로 토큰이 빠르게 소모된다
# (2026-07-27: 전체 측정 1회로 세션 토큰 예산이 급감). 사고를 막기 위해 두 겹으로 막는다.
#   1) 세션 수 상한: 기본 30개를 넘으면 거부하고, 올리려면 ROUTING_MAX_SESSIONS 를 명시해야 한다.
#   2) 실행 승인: 대화형 터미널이면 직접 묻고, 비대화형(에이전트 도구 호출, CI, 훅)이면
#      ROUTING_MEASURE_CONFIRM=yes 가 없는 한 무조건 거부한다. 에이전트 실행에는 TTY 가
#      없으므로(2026-07-27 확인) 이 조건 하나로 "에이전트가 무심코 돌리는" 경로가 막힌다.
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
    echo "[BLOCKED] 비대화형 실행은 기본 차단됩니다(에이전트 도구 호출, CI, 훅 등)." >&2
    echo "          토큰이 소모되는 작업이므로 사용자의 명시적 승인이 필요합니다." >&2
    echo "          의도한 실행이라면 ROUTING_MEASURE_CONFIRM=yes 를 붙이십시오." >&2
    echo "            예) ROUTING_MEASURE_CONFIRM=yes bash ${BASH_SOURCE[0]} M02 M03" >&2
    exit 3
  fi
fi

echo "[INFO] 실행 파일: $CLI"
echo "[INFO] 케이스 ${#ids[@]}건 x ${REPEATS}회 = ${PLANNED}회 실행, 동시 ${JOBS}개, 1회당 제한 ${TIMEOUT_SEC}초"

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
