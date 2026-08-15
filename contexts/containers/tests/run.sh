#!/usr/bin/env bash
# containers 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 010-containers-core.md / 020-image-hardening-standard.md 의 특정
# 조항이나 중단 조건을 재현한다. 목적은 pre-flight-check.sh 의 Dockerfile 검증
# 로직을 손볼 때, 기존 검사가 조용히 죽어서 위반 이미지 정의가 통과되는 상황을
# 제어하는 것이다.
#
# 검증기가 스테이징된 파일을 대상으로 동작하는 것과 달리 이 러너는 픽스처를
# 직접 넘긴다. 대신 검증기가 쓰는 것과 동일한 명령·옵션을 그대로 사용한다.
#
# 두 검증기의 강제력이 다르므로 그룹을 나눠 표기한다.
#   hadolint         validate_docker 가 실패 시 커밋을 중단한다 (중단 게이트)
#   trivy misconfig  validate_security 가 --exit-code 0 으로 호출하므로 커밋을
#                    막지 않는다. 탐지 여부만 검증한다 (경고 전용)
#
# validate_security 는 저장소 전체를 훑을 때 --skip-dirs 로 tests/fixtures 를 제외하므로
# 이 픽스처들은 파이프라인의 저장소 스캔에는 잡히지 않는다. 일부러 위반하도록 만든 파일이
# 매 커밋 재보고되는 노이즈를 막기 위한 것이고, 스캐너와 심각도 필터가 실제로 DS-0002 를
# 탐지하는지는 여기서 픽스처를 직접 넘겨 검증한다(다운스트림 프로젝트에서는 픽스처 밖
# 경로이므로 그대로 스캔 대상이다).
#
# trivy secret 스캐너용 픽스처는 두지 않는다. 실제로 탐지되는 자격 증명을
# 저장소에 두는 셈이라 시크릿 하드코딩 통제 규칙에 정면으로 어긋나고,
# pre-commit 훅의 trufflehog 가 커밋 자체를 중단한다.
#
# 사용: bash ~/dotfiles/contexts/containers/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/parallel-pair.sh"
# EXIT 트랩을 서로 덮어쓰지 않고 겹쳐 쓰기 위한 SSOT (exit-trap.sh 헤더 참조).
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/exit-trap.sh"

PASS_COUNT=0
FAIL_COUNT=0
CHECKED=()

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
require_tool() {
  command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치 또는 현재 위치에서 실행 실패: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

report() {
  local name=$1 ok=$2 detail=${3:-}
  CHECKED+=("$name")
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# pre-flight-check.sh 의 validate_docker 와 동일하게 'hadolint <file>' 를 호출한다.
# want_rule 이 빈 문자열이면 지적 0건을 기대한다.
run_hadolint() {
  local name=$1 want_rule=${2:-}
  local out status rules
  out=$(hadolint "$FIXTURES/$name" 2>&1) && status=0 || status=$?
  # 지적 0건이면 grep 이 1을 반환해 set -e 에 걸리므로 반드시 흡수해야 한다.
  rules=$(grep -oE 'DL[0-9]+|SC[0-9]+' <<<"$out" | sort -u | tr '\n' ' ' || true)

  if [ -z "$want_rule" ]; then
    if [ "$status" -eq 0 ]; then
      report "$name" 0
    else
      report "$name" 1 "기대: 지적 0건 / 실제: $rules"
    fi
    return
  fi

  if [ "$status" -ne 0 ] && grep -q "$want_rule" <<<"$out"; then
    report "$name" 0
  else
    report "$name" 1 "기대: $want_rule 지적 / 실제 exit=$status, rules=$rules"
  fi
}

# validate_security 의 '--severity HIGH,CRITICAL --scanners misconfig' 와 동일한
# 심각도 필터를 적용한다. want_id 가 빈 문자열이면 HIGH 이상 탐지 0건을 기대한다.
PY_EXTRACT_MISCONFIG_IDS='
import json,sys
d=json.load(sys.stdin)
print(" ".join(sorted({m["ID"] for r in d.get("Results",[]) for m in r.get("Misconfigurations",[])})))
'

judge_trivy_misconfig() {
  local name=$1 want_id=$2 ids=$3
  if [ "$ids" = "__SCAN_ERROR__" ]; then
    report "$name" 1 "trivy config 실행 또는 결과 파싱에 실패했습니다"
    return
  fi
  if [ -z "$want_id" ]; then
    if [ -z "$ids" ]; then
      report "$name" 0
    else
      report "$name" 1 "기대: HIGH 이상 탐지 0건 / 실제: $ids"
    fi
    return
  fi
  if grep -q " $want_id " <<<" $ids "; then
    report "$name" 0
  else
    report "$name" 1 "기대: $want_id 탐지 / 실제: ${ids:-(없음)}"
  fi
}

# trivy config 는 인터프리터 없는 Go 바이너리라 개별 호출은 빠르지만, 아래 두 쌍
# (misconfig, hardening-gate)이 각각 2번씩 순차 호출되면 누적된다. parallel-pair.sh
# (SSOT)로 ok/fail 픽스처를 동시에 스캔하고, JSON 파싱(python3)만 캡처된 파일에 대해
# wait 이후 순차로 수행한다(파싱 자체는 가벼워 병렬화 대상이 아님).
run_trivy_misconfig_pair() {
  local ok_name=$1 fail_name=$2 want_id=${3:-}
  local tmpdir ok_status fail_status ok_ids fail_ids
  tmpdir=$(mktemp -d)
  # `trap ... EXIT` 는 추가가 아니라 교체라, 이 스크립트의 두 pair 함수가 서로의 트랩을
  # 덮어쓴다. push/pop 으로 감싸 직전 상태를 정확히 복원한다 (exit-trap.sh 헤더 참조).
  # 홑따옴표가 맞다: 트랩 본문은 발동 시점에 전개돼야 한다.
  # shellcheck disable=SC2016
  push_exit_trap 'rm -rf "${tmpdir:-}"'

  # shellcheck disable=SC2034,SC2016 # nameref로 간접 참조됨 / $1은 bash -c 서브셸 안에서 확장돼야 함
  CMD_OK=(bash -c 'trivy config --quiet --severity HIGH,CRITICAL --format json "$1" 2>/dev/null' _ "$FIXTURES/$ok_name")
  # shellcheck disable=SC2034,SC2016
  CMD_FAIL=(bash -c 'trivy config --quiet --severity HIGH,CRITICAL --format json "$1" 2>/dev/null' _ "$FIXTURES/$fail_name")
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$tmpdir/ok" "$tmpdir/fail"

  ok_ids=$(python3 -c "$PY_EXTRACT_MISCONFIG_IDS" <"$tmpdir/ok" 2>/dev/null) || ok_ids="__SCAN_ERROR__"
  fail_ids=$(python3 -c "$PY_EXTRACT_MISCONFIG_IDS" <"$tmpdir/fail" 2>/dev/null) || fail_ids="__SCAN_ERROR__"

  judge_trivy_misconfig "$ok_name" "" "$ok_ids"
  judge_trivy_misconfig "$fail_name" "$want_id" "$fail_ids"

  rm -rf "$tmpdir"
  pop_exit_trap
}

# pre-flight-check.sh 의 validate_docker 와 동일하게 container-hardening-gate.sh 에
# Dockerfile 경로를 그대로 넘긴다. want_code 는 기대 종료 코드(0=통과, 1=차단)다.
run_hardening_gate_pair() {
  local ok_name=$1 ok_want=$2 fail_name=$3 fail_want=$4
  local tmpdir ok_status fail_status
  tmpdir=$(mktemp -d)
  # `trap ... EXIT` 는 추가가 아니라 교체라, 이 스크립트의 두 pair 함수가 서로의 트랩을
  # 덮어쓴다. push/pop 으로 감싸 직전 상태를 정확히 복원한다 (exit-trap.sh 헤더 참조).
  # 홑따옴표가 맞다: 트랩 본문은 발동 시점에 전개돼야 한다.
  # shellcheck disable=SC2016
  push_exit_trap 'rm -rf "${tmpdir:-}"'

  # shellcheck disable=SC2034
  CMD_OK=(bash "$REPO_ROOT/bin/linters/container-hardening-gate.sh" "$FIXTURES/$ok_name")
  # shellcheck disable=SC2034
  CMD_FAIL=(bash "$REPO_ROOT/bin/linters/container-hardening-gate.sh" "$FIXTURES/$fail_name")
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$tmpdir/ok" "$tmpdir/fail"

  if [ "$ok_status" -eq "$ok_want" ]; then
    report "$ok_name" 0
  else
    report "$ok_name" 1 "기대 exit=$ok_want / 실제 exit=$ok_status"
  fi
  if [ "$fail_status" -eq "$fail_want" ]; then
    report "$fail_name" 0
  else
    report "$fail_name" 1 "기대 exit=$fail_want / 실제 exit=$fail_status"
  fi

  rm -rf "$tmpdir"
  pop_exit_trap
}

echo "=== containers 검증 파이프라인 회귀 테스트 ==="

# 이 섹션이 실제로 지키는 것은 "hadolint 가 우리가 의존하는 룰 ID 를 여전히 낸다"는
# 도구 의존 계약이다(우리 코드는 경유하지 않는다). Renovate 가 mise 도구 버전을 매주
# 자동으로 올리므로 그 계약은 실제로 흔들리고, 계약이 깨지면 pre-flight 게이트가 조용히
# 아무것도 막지 않게 된다 — 그래서 남긴다.
# 다만 대표 ID 하나면 충분하다. 도구가 룰 셋을 개편하면 여러 ID 가 같이 바뀌지 하나만
# 바뀌지 않으므로, ID 를 늘려도 잡히는 사건은 같고 픽스처 관리 비용만 는다.
# (DL3018/DL3025 케이스와 그 픽스처는 이 근거로 제거했다.)
echo "--- hadolint (pre-flight-check.sh / 커밋 중단) ---"
if require_tool hadolint; then
  run_hadolint ok-baseline.Dockerfile ""
  run_hadolint fail-unpinned-base.Dockerfile DL3007
fi

echo "--- trivy misconfig (pre-flight-check.sh / 경고 전용) ---"
if require_tool trivy; then
  run_trivy_misconfig_pair ok-baseline.Dockerfile fail-root-user.Dockerfile DS-0002
fi

echo "--- container-hardening-gate.sh DS-0002 (pre-flight-check.sh / 커밋 중단) ---"
if require_tool trivy; then
  run_hardening_gate_pair ok-baseline.Dockerfile 0 fail-root-user.Dockerfile 1
fi

# 스캐너가 죽었을 때 "위반 없음"과 구분하지 못하고 통과시키면, 하드 블록 게이트가
# 조용히 무력화된다. 예전엔 trivy 를 파이프 왼쪽에 두고 통째로 if 조건에 넣어서, trivy 가
# 실패하면 jq 가 빈 입력을 받아 1을 반환하고 그대로 "통과"로 흘렀다(if 조건문 안이라
# set -e 도 개입 못 함). trivy 를 실패하는 스텁으로 바꿔 차단되는지 고정한다.
echo "--- container-hardening-gate.sh 스캐너 실패 시 차단 (무검증 통과 방지) ---"
stub_dir=$(mktemp -d)
cat >"$stub_dir/trivy" <<'STUB_EOF'
#!/usr/bin/env bash
# has_tool 의 --version 조회는 통과시키고, 실제 스캔만 실패시킨다.
[ "${1:-}" = "--version" ] && exit 0
exit 3
STUB_EOF
chmod +x "$stub_dir/trivy"
stub_status=0
PATH="$stub_dir:$PATH" bash "$REPO_ROOT/bin/linters/container-hardening-gate.sh" \
  "$FIXTURES/ok-baseline.Dockerfile" >"$stub_dir/out" 2>&1 || stub_status=$?
if [ "$stub_status" -ne 0 ] && grep -qF "판정을 내릴 수 없습니다" "$stub_dir/out"; then
  report "scanner-failure-blocks (trivy 실패 시 통과시키지 않음)" 0
else
  report "scanner-failure-blocks (trivy 실패 시 통과시키지 않음)" 1 \
    "exit=$stub_status out=$(cat "$stub_dir/out")"
fi
rm -rf "$stub_dir"

# 기대 결과가 등록되지 않은 픽스처는 검증되지 않은 채 방치된다.
for path in "$FIXTURES"/*.Dockerfile; do
  name=$(basename "$path")
  found=0
  for c in "${CHECKED[@]}"; do [ "$c" = "$name" ] && found=1 && break; done
  [ "$found" -eq 0 ] && echo "  WARN  $name — 기대 결과가 등록되지 않은 픽스처입니다"
done

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
