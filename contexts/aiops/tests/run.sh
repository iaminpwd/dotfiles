#!/usr/bin/env bash
# aiops 스킬 회귀 테스트
#
# 기존 버전은 데모 스크립트 3개를 그냥 실행해 "크래시하지 않으면 통과"로 판정했다.
# assert도 fixture도 없어서, FinancialDataAnonymizer의 계좌번호 마스킹 정규식을
# 완전히 무력화해도(never-matches 패턴으로 치환) 원본 계좌번호가 로그에 그대로
# 찍힌 채로 "All AIOps tests passed successfully"가 나왔다(2026-08-01 실측).
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
# 2026-08-01 실측: 계좌번호 정규식을 무력화해도 이 단언이 없어 "크래시 안 함"만으로
# 통과 처리됐다.
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
