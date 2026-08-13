#!/usr/bin/env bash
# run-suite.sh
# 저장소의 모든 검증 스크립트(pre-flight-check.sh 등)를 묶어서 실행하는 러너.
# 범용 환경에서 토큰 절약을 위해 텍스트 출력을 컴팩트하게 변환한다.
#
# 합격/불합격은 래핑 대상 스크립트의 "종료 코드(exit code)"로만 판정 (거짓 통과 방지)
#
# 항목별 전체 결과를 보여주기 위해 개별 실패 시에도 남은 검증을 계속 진행

set -euo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
RS_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$RS_SCRIPT_DIR/../lib/script-init.sh"

# 이 스크립트가 실행된 현재 저장소의 루트를 찾음 (script-init.sh SSOT 재사용)
init_repo_root

# 검증할 스크립트 목록 수집
SCRIPTS=()

# --pfc-args=<값>: pre-flight-check.sh로 전달되는 패스스루 인자 (다중 지정 가능)
PFC_ARGS=()

for arg in "$@"; do
  if [[ "$arg" == --pfc-args=* ]]; then
    PFC_ARGS+=("${arg#--pfc-args=}")
  else
    SCRIPTS+=("$arg")
  fi
done

# PATH에서 찾지 못해 목록에서 빠진 게이트. 조용히 빠지면 "돌지도 않은 검증"이 통과로
# 보이므로(아래 add_default_gate 주석) 마지막 요약에서 한 번 더 드러낸다.
MISSING_GATES=()

# add_default_gate <스크립트명>
# PATH에 있으면 실행 목록에 넣고, 없으면 경고를 남긴다.
# 예전엔 `command -v ... && SCRIPTS+=(...)` 뿐이라 미설치 시 아무 말 없이 빠졌다. 아래
# "대상 0건" 가드는 run.sh 들이 잡히면 발동하지 않으므로, ai_agent 롤이 아직 안 돌아간
# 새 클론에서 `just verify` 가 저장소 전체 스캔·프롬프트 린트·커버리지 게이트를 한 번도
# 안 돌린 채 초록불만 띄웠다(실측: 15개여야 할 대상이 12개로 줄었는데 아무 표시 없음).
add_default_gate() {
  local name=$1
  if command -v "$name" >/dev/null 2>&1; then
    SCRIPTS+=("$name")
  else
    echo "[WARNING] $name 을(를) PATH에서 찾지 못해 이 검증을 건너뜁니다." >&2
    MISSING_GATES+=("$name")
  fi
}

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  # 인자가 없으면 디폴트로 저장소 내 모든 테스트 및 pre-flight 스캔 수집
  # 1. 공통 필수: pre-flight-check.sh (어느 환경에서든 실행)
  add_default_gate pre-flight-check.sh

  # 2. dotfiles 저장소인 경우 예외적으로 prompt-lint.sh, test-coverage-check.sh 추가
  if [ "$(basename "$REPO_ROOT")" = "dotfiles" ]; then
    add_default_gate prompt-lint.sh
    add_default_gate test-coverage-check.sh
  fi

  # 3. 현재 저장소 내부의 모든 tests/run.sh 추가
  # 숨김 디렉토리(.archive, .git 등) 하위는 제외한다. 호출부인 Justfile의 `just test`는
  # 셸 글롭(contexts/*/tests/run.sh)으로 대상을 모으는데 글롭은 dotglob 없이는 숨김
  # 디렉토리를 건너뛰는 반면 find는 그러지 않아, 같은 저장소에서 `just test`(12개)와
  # `just verify`/CI/pre-push(13개)가 서로 다른 집합을 돌리고 있었다. 그 차이가
  # contexts/.archive/ — 폐기해 치워둔 스킬 — 라서, 쓰지도 않는 스킬의 회귀 테스트가
  # CI에서만 계속 돌며 빌드를 깨뜨릴 수 있었다. 탐색 기준을 글롭 쪽 의미론에 맞춘다.
  # -mindepth 1: 저장소 루트 자신의 이름이 점으로 시작해도(예: ~/.dotfiles) 전체가
  # prune되지 않도록 판정 대상에서 시작점을 뺀다.
  while IFS= read -r -d '' script; do
    SCRIPTS+=("$script")
  done < <(find "$REPO_ROOT" -mindepth 1 -type d -name '.*' -prune -o -name "run.sh" -path "*/tests/run.sh" -print0 2>/dev/null | sort -z || true)
fi

# 대상 스크립트가 없으면 무검증 통과 방지를 위해 명시적으로 경고 후 중단(exit 1)
if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  echo "[ERROR] 실행할 검증 스크립트를 찾지 못했습니다 (탐색 기준: $REPO_ROOT)." >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# 각 스크립트는 서로 무관한 격리된 검증(자기 mktemp 픽스처만 사용)이라 병렬 실행이
# 안전하다. 동시성은 가용 코어 수를 기본값으로 쓰고 RUN_SUITE_JOBS로 조정 가능하다.
NPROC="${RUN_SUITE_JOBS:-}"
if [ -z "$NPROC" ]; then
  NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

# 1 이상의 정수가 아니면 기본값으로 되돌린다. 아래 배치 루프는 end=$((i + NPROC)) 로 전진하는데
# NPROC이 0이나 음수면 end가 i보다 커지지 않아 루프가 영원히 끝나지 않는다(실측: RUN_SUITE_JOBS=0,
# RUN_SUITE_JOBS=-1 둘 다 타임아웃). 이 러너는 pre-commit/pre-push/Stop 훅이 모두 경유하므로
# 그 상태가 되면 커밋과 푸시가 아무 메시지 없이 영구 정지한다. nproc/sysctl 결과도 같은 기준으로
# 함께 검사해 판정 지점을 한 곳으로 모은다.
if ! [[ "$NPROC" =~ ^[1-9][0-9]*$ ]]; then
  echo "[WARNING] 동시 실행 수가 유효하지 않아(값='$NPROC') 기본값 4로 대체합니다." >&2
  NPROC=4
fi

run_script() {
  local script="$1" out_file="$2"
  local cmd
  if [ -f "$script" ]; then
    cmd=(bash "$script")
  else
    cmd=("$script")
  fi
  if [[ "$script" == *"pre-flight-check.sh"* ]] && [ "${#PFC_ARGS[@]}" -gt 0 ]; then
    "${cmd[@]}" "${PFC_ARGS[@]}" >"$out_file" 2>&1
  else
    "${cmd[@]}" >"$out_file" 2>&1
  fi
}

TOTAL="${#SCRIPTS[@]}"
declare -a RCS

# NPROC개씩 배치로 묶어 병렬 실행한다. 배치 안의 PID는 그 배치에서만 wait 하므로
# (wait -n 처럼 이미 reap된 PID를 다시 기다리는 이중 대기 문제가 없다) 종료 코드
# 캡처가 항상 정확하다.
i=0
while [ "$i" -lt "$TOTAL" ]; do
  BATCH_PIDS=()
  BATCH_IDX=()
  end=$((i + NPROC))
  [ "$end" -le "$TOTAL" ] || end=$TOTAL
  for ((j = i; j < end; j++)); do
    run_script "${SCRIPTS[$j]}" "$WORKDIR/out.$j" &
    BATCH_PIDS+=("$!")
    BATCH_IDX+=("$j")
  done
  for k in "${!BATCH_PIDS[@]}"; do
    rc=0
    wait "${BATCH_PIDS[$k]}" || rc=$?
    RCS[${BATCH_IDX[$k]}]=$rc
  done
  i=$end
done

FAILED=()

# 병렬 실행 자체는 완료 순서가 뒤섞이지만, 보고는 항상 SCRIPTS 원래 순서대로
# 해 출력을 결정적으로 유지한다.
for idx in "${!SCRIPTS[@]}"; do
  script="${SCRIPTS[$idx]}"
  # 출력 가독성을 위해 절대 경로에서 REPO_ROOT 또는 HOME 경로를 제거
  SCRIPT_NAME="${script#"$REPO_ROOT"/}"
  SCRIPT_NAME="${SCRIPT_NAME#"$HOME"/}"
  rc="${RCS[$idx]}"
  out_file="$WORKDIR/out.$idx"

  if [ "$rc" -eq 0 ]; then
    # 통과: 경고(WARNING/도구 미설치 등)만 남기고 나머지 정상/통계 로그는 억제
    grep -aE '^[[:space:]]*(\[WARNING\]|⚠)' "$out_file" | sed 's/^[[:space:]]*/  /' || true
    printf '  -> [✓] %s\n' "$SCRIPT_NAME"
  else
    FAILED+=("$SCRIPT_NAME")
    # 실패 시에는 압축하지 않고 원형 로그를 그대로 보존한다(디버깅 추적성 확보).
    printf '❌ [%s] exit=%s ------------------------------------------\n' "$SCRIPT_NAME" "$rc"
    cat "$out_file"
    printf -- '----------------------------------------------------------------\n'
  fi
done

# 건너뛴 게이트는 판정 바로 옆에서 한 번 더 알린다. 위쪽 수집 시점의 경고는 개별
# 스크립트 출력에 파묻혀 스크롤을 타고 지나가기 때문이다.
if [ "${#MISSING_GATES[@]}" -gt 0 ]; then
  echo "[WARNING] 아래 검증은 PATH에 없어 이번 실행에서 수행되지 않았습니다 — 통과 표시는 이 항목들을 포함하지 않습니다:" >&2
  echo "[WARNING]    ${MISSING_GATES[*]}" >&2
  echo "[WARNING]    (dotfiles 저장소에서 'just setup' 으로 ai_agent 롤을 돌리면 ~/.local/bin 에 링크됩니다)" >&2
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '❌ 검증 실패 %s/%s: %s\n' "${#FAILED[@]}" "${#SCRIPTS[@]}" "${FAILED[*]}" >&2
  exit 1
fi
