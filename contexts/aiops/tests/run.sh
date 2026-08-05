#!/usr/bin/env bash
# aiops 스킬 회귀 테스트
#
# 데모 스크립트를 그냥 실행해 "크래시하지 않으면 통과"로 판정하는 방식은 위험하다.
# assert도 fixture도 없으면, FinancialDataAnonymizer의 계좌번호 마스킹 정규식을
# 완전히 무력화해도(never-matches 패턴으로 치환) 원본 계좌번호가 로그에 그대로
# 찍힌 채로 "All AIOps tests passed successfully"가 나올 수 있다.
#
# 세 검증 대상을 각각 실제로 잡아낼 수 있게 다시 짰다:
#   1. validate-telemetry-schema.sh: ok-baseline/fail-hardcoded-secret 픽스처로
#      checkov류 라이브러리와 동일한 want_fail 단언 패턴을 적용.
#   2. eval-anomaly-threshold.py: calculate_dynamic_threshold를 importlib으로
#      직접 임포트해 손계산한 기대값과 대조.
#   3. anomaly-rag-pipeline.py: FinancialDataAnonymizer.sanitize를 importlib으로
#      직접 임포트해 RRN/카드/계좌 마스킹이 실제로 원본을 제거하는지 확인.
#
# 파일명에 하이픈이 있어 일반 import 문을 못 쓰므로(eval-anomaly-threshold.py,
# anomaly-rag-pipeline.py) importlib.util로 로드한다.
#
# 사용: bash ~/dotfiles/contexts/aiops/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures/telemetry"

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

echo "=== aiops 회귀 테스트 ==="

echo "--- validate-telemetry-schema.sh ---"

status=0
bash "$SKILL_ROOT/scripts/validate-telemetry-schema.sh" "$FIXTURES/ok-baseline" >/dev/null 2>&1 || status=$?
if [ "$status" -eq 0 ]; then report "ok-baseline (지적 0건)" 0; else report "ok-baseline (지적 0건)" 1 "기대 exit=0 / 실제 exit=$status"; fi

status=0
out=$(bash "$SKILL_ROOT/scripts/validate-telemetry-schema.sh" "$FIXTURES/fail-hardcoded-secret" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "Plaintext secrets detected" <<<"$out"; then
  report "fail-hardcoded-secret (평문 시크릿 차단)" 0
else
  report "fail-hardcoded-secret (평문 시크릿 차단)" 1 "기대 exit=1 + 시크릿 탐지 문구 / 실제 exit=$status"
fi

# password_policy/secret_key_rotation_enabled 처럼 시크릿 "값"이 아니라 필드 "이름"에만
# 키워드가 부분 문자열로 들어간 경우는 통과해야 한다(오탐 고정 회귀).
status=0
bash "$SKILL_ROOT/scripts/validate-telemetry-schema.sh" "$FIXTURES/ok-benign-identifiers" >/dev/null 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-benign-identifiers (필드명뿐인 password_policy 등은 오탐 없음)" 0
else
  report "ok-benign-identifiers (필드명뿐인 password_policy 등은 오탐 없음)" 1 "기대 exit=0 / 실제 exit=$status"
fi

echo "--- aiops-check.sh (bin/hooks/plugins, 커밋 시점 배선) ---"
# validate-telemetry-schema.sh는 bin/hooks/plugins/*.sh로 배선된 aiops-check.sh를 통해
# 실제 git commit 경로에서 호출된다. 그 오케스트레이션 로직(kind: 시그니처 트리거 판정,
# 격리 tmpdir 구성, 동반 파일 배치 스캔)까지 여기서 실제로 검증한다.
AIOPS_PLUGIN="$REPO_ROOT/bin/hooks/plugins/aiops-check.sh"
if [ -x "$AIOPS_PLUGIN" ]; then
  PLUGIN_TMP=$(mktemp -d)

  run_plugin() {
    local repo=$1 status=0
    (cd "$repo" && QUIET=0 bash "$AIOPS_PLUGIN") >"$PLUGIN_TMP/out" 2>&1 || status=$?
    echo "$status"
  }

  # Case 1: kind: TelemetryCollectorConfig + 평문 시크릿이 함께 스테이징되면 차단해야 한다.
  R1="$PLUGIN_TMP/repo1"
  mkdir -p "$R1"
  git -C "$R1" init -q
  git -C "$R1" config user.email test@example.com
  git -C "$R1" config user.name Test
  cp "$FIXTURES/fail-hardcoded-secret/manifest.yaml" "$R1/manifest.yaml"
  git -C "$R1" add manifest.yaml
  status=$(run_plugin "$R1")
  if [ "$status" -eq 1 ] && grep -qF "AIOps 텔레메트리 매니페스트 검증" "$PLUGIN_TMP/out"; then
    report "trigger-and-block (kind: 시그니처 + 평문 시크릿 -> 커밋 차단)" 0
  else
    report "trigger-and-block (kind: 시그니처 + 평문 시크릿 -> 커밋 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  # Case 2: kind: ClosedLoopPolicy + 시크릿 없음 -> 통과해야 한다.
  R2="$PLUGIN_TMP/repo2"
  mkdir -p "$R2"
  git -C "$R2" init -q
  git -C "$R2" config user.email test@example.com
  git -C "$R2" config user.name Test
  cp "$FIXTURES/ok-baseline/manifest.yaml" "$R2/manifest.yaml"
  git -C "$R2" add manifest.yaml
  status=$(run_plugin "$R2")
  if [ "$status" -eq 0 ]; then
    report "trigger-and-pass (kind: 시그니처 + 시크릿 없음 -> 통과)" 0
  else
    report "trigger-and-pass (kind: 시그니처 + 시크릿 없음 -> 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  # Case 3: 무관한 kind:(텔레메트리 시그니처 아님)는 시크릿이 있어도 트리거 자체가 안 돼야
  # 한다(저장소 전체를 매 커밋마다 훑는 것을 방지하려는 설계 의도를 고정).
  R3="$PLUGIN_TMP/repo3"
  mkdir -p "$R3"
  git -C "$R3" init -q
  git -C "$R3" config user.email test@example.com
  git -C "$R3" config user.name Test
  cat >"$R3/deployment.yaml" <<'EOF'
kind: Deployment
metadata:
  name: unrelated
spec:
  password: hunter2
EOF
  git -C "$R3" add deployment.yaml
  status=$(run_plugin "$R3")
  if [ "$status" -eq 0 ]; then
    report "no-trigger-on-unrelated-kind (텔레메트리 시그니처 아니면 무동작)" 0
  else
    report "no-trigger-on-unrelated-kind (텔레메트리 시그니처 아니면 무동작)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  # Case 4: kind: 매니페스트는 깨끗해도, 같은 커밋에 함께 스테이징된 .tf에 시크릿이 있으면
  # 트리거된 배치 스캔이 그것까지 잡아야 한다(스캔 대상이 kind: 파일 하나로 좁혀지지
  # 않고 함께 스테이징된 전체를 본다는 설계를 고정).
  R4="$PLUGIN_TMP/repo4"
  mkdir -p "$R4"
  git -C "$R4" init -q
  git -C "$R4" config user.email test@example.com
  git -C "$R4" config user.name Test
  cp "$FIXTURES/ok-baseline/manifest.yaml" "$R4/manifest.yaml"
  cat >"$R4/main.tf" <<'EOF'
resource "example_secret" "leak" {
  password = "hunter2"
}
EOF
  git -C "$R4" add manifest.yaml main.tf
  status=$(run_plugin "$R4")
  if [ "$status" -eq 1 ]; then
    report "batch-scan-sibling-tf (kind: 파일은 깨끗해도 동반 .tf 시크릿을 함께 잡음)" 0
  else
    report "batch-scan-sibling-tf (kind: 파일은 깨끗해도 동반 .tf 시크릿을 함께 잡음)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  rm -rf "$PLUGIN_TMP"
else
  report "aiops-check.sh 플러그인 배선 확인" 1 "bin/hooks/plugins/aiops-check.sh 를 찾을 수 없거나 실행 권한이 없습니다"
fi

echo "--- eval-anomaly-threshold.py (calculate_dynamic_threshold) ---"

py_status=0
python3 - "$SKILL_ROOT/scripts/eval-anomaly-threshold.py" <<'PY' || py_status=$?
import importlib.util
import sys

mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("eval_anomaly_threshold", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
calc = mod.calculate_dynamic_threshold

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}")
        if detail:
            print(f"        {detail}")
        failures.append(name)


# 1. 빈 입력: 크래시 없이 전부 0이어야 한다.
r = calc([])
check("empty-input (전부 0)", r == {"mean": 0, "std_dev": 0, "upper_bound": 0, "lower_bound": 0}, str(r))

# 2. 균일 데이터: 표준편차 0, 이상치 0건.
r = calc([5, 5, 5, 5], sigma=3.0)
check(
    "uniform-data (표준편차 0, 이상치 0건)",
    r["std_dev"] == 0 and r["anomaly_count"] == 0 and r["upper_bound"] == 5 and r["lower_bound"] == 5,
    str(r),
)

# 3. 손계산 대조: [1,2,3,4,5], sigma=1 -> mean=3, std_dev=sqrt(2)=1.41,
#    upper=4.41, lower=1.59, 1과 5가 경계를 벗어나 이상치 2건.
r = calc([1, 2, 3, 4, 5], sigma=1.0)
check(
    "known-dataset (손계산 대조)",
    r["mean"] == 3.0 and r["std_dev"] == 1.41 and r["upper_bound"] == 4.41 and r["lower_bound"] == 1.59 and r["anomaly_count"] == 2,
    str(r),
)

sys.exit(1 if failures else 0)
PY
if [ "$py_status" -eq 0 ]; then report "calculate_dynamic_threshold 단위 테스트" 0; else report "calculate_dynamic_threshold 단위 테스트" 1 "위 PASS/FAIL 로그 참고"; fi

echo "--- anomaly-rag-pipeline.py (FinancialDataAnonymizer) ---"

py_status=0
python3 - "$SKILL_ROOT/examples/anomaly-rag-pipeline.py" <<'PY' || py_status=$?
import importlib.util
import sys

mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("anomaly_rag_pipeline", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sanitize = mod.FinancialDataAnonymizer.sanitize

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}")
        if detail:
            print(f"        {detail}")
        failures.append(name)


# 각 케이스: 마스킹 마커가 등장하고, 원본 민감값은 결과에 남아있지 않아야 한다.
# 이 단언이 없으면 계좌번호 정규식을 무력화해도 "크래시 안 함"만으로 통과 처리된다.
cases = [
    ("RRN 마스킹", "RRN 900101-1234567 detected", "900101-1234567", "[MASKED_RRN]"),
    ("카드번호 마스킹", "Card 4111 1111 1111 1111 used", "4111 1111 1111 1111", "[MASKED_CARD_NUMBER]"),
    ("계좌번호 마스킹", "account 123-45-67890 error", "123-45-67890", "[MASKED_ACCOUNT_NUMBER]"),
]
for name, raw, sensitive, marker in cases:
    out = sanitize(raw)
    check(name, sensitive not in out and marker in out, f"sanitize({raw!r}) -> {out!r}")

# 과잉 마스킹 회귀: PII가 없는 평범한 텍스트는 그대로 통과해야 한다.
plain = "Connection timed out with no PII here."
check("PII 없는 텍스트는 원형 보존", sanitize(plain) == plain, f"sanitize({plain!r}) -> {sanitize(plain)!r}")

sys.exit(1 if failures else 0)
PY
if [ "$py_status" -eq 0 ]; then report "FinancialDataAnonymizer 단위 테스트" 0; else report "FinancialDataAnonymizer 단위 테스트" 1 "위 PASS/FAIL 로그 참고"; fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
