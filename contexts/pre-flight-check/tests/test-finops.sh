#!/usr/bin/env bash
# test-finops.sh
#
# validate_finops_costs(bin/lib/pfc-quality-checks.sh, pre-flight-check.sh가 source)
# 의 실질 커스텀 로직은 infracost 자체가 아니라 "출력에 Extended Support/LTS 문구가
# 있으면 커밋을 막는다"는 grep 판정이다. RUN_COST_CHECK 게이트와 스테이징 캐시 히트
# 로직은 제어 흐름일 뿐이라 여기서 다시 검증하지 않고, 그 판정이 실제로 맞물리는지만
# 고정한다. AWS RDS 엔진 버전으로 "지원 종료 아님"을 표현하면 AWS가 Extended Support
# 대상을 계속 넓혀 픽스처가 시간이 지나며 저절로 위반으로 변질되므로, ok-baseline 은
# Extended Support 개념이 아예 없는 S3 버킷으로 잡았다(자세한 사유는
# fixtures-finops/ok-baseline/main.tf 주석 참고).
#
# infracost 무료 티어를 쓰므로 이 검증은 실제 커밋 시점(RUN_COST_CHECK=true, git/
# .githooks/pre-commit 이 켬)에만 API를 두 번 호출하고, `just test`/수동 실행 등
# 평소 개발 루프에서는 건너뛴다. validate_finops_costs 본체와 동일한 게이트를
# 재사용한 것이다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-finops.sh
# 실제 실행: RUN_COST_CHECK=true bash ~/dotfiles/contexts/pre-flight-check/tests/test-finops.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

# 판정 패턴은 검증기 본체에서 가져온다. 예전엔 이 테스트가 같은 정규식을 손으로 복제해
# 갖고 있었는데, 그러면 본체만 고쳤을 때 테스트가 그대로 통과해 회귀를 못 잡는다.
# (source 전용 라이브러리라 함수 정의와 이 상수만 들어오고 부작용은 없다.)
# shellcheck source=../../../bin/lib/pfc-quality-checks.sh
source "$REPO_ROOT/bin/lib/pfc-quality-checks.sh"

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

echo "--- FinOps 판정 패턴 (API 호출 없음, 항상 실행) ---"

# 이 판정은 지금까지 RUN_COST_CHECK=true 일 때만 검증됐다. 그래서 평소 `just test` 에서는
# 정규식이 깨져도 아무도 몰랐고, 실제로 깨져 있었다 — 단어 경계 없는 `LTS` 가 부분 문자열로
# "lts" 를 품는 흔한 단어를 전부 잡아, `aws_s3_bucket.results` 한 줄로 커밋이 막혔다.
# infracost 를 부르지 않고 판정식만 직접 태워 그 축을 상시 고정한다.
pattern_case() {
  local name=$1 want=$2 line=$3 got
  if grep -E -qi "$PFC_EXTENDED_SUPPORT_PATTERN" <<<"$line"; then got=match; else got=nomatch; fi
  if [ "$got" = "$want" ]; then
    report "$name" 0
  else
    report "$name" 1 "기대 $want / 실제 $got — 입력: $line"
  fi
}

pattern_case "match: Extended Support"        match   "aws_rds_cluster.main  RDS Extended Support  \$100.00"
pattern_case "match: Long Term Support"       match   "Ubuntu Long Term Support subscription"
pattern_case "match: 독립 토큰 LTS"           match   "ubuntu_pro.this  Ubuntu Pro LTS  \$25.00"
pattern_case "nomatch: results (오탐 회귀)"   nomatch "aws_s3_bucket.results"
pattern_case "nomatch: defaults (오탐 회귀)"  nomatch "module.defaults.aws_vpc.this"
pattern_case "nomatch: vaults (오탐 회귀)"    nomatch "aws_backup_vaults.archive"

echo
echo "--- FinOps 비용 검증 (validate_finops_costs) ---"

if [ "${RUN_COST_CHECK:-false}" != "true" ]; then
  echo "  [INFO] RUN_COST_CHECK가 아니어서 FinOps 검증을 건너뜁니다 (무료 티어 API 호출 절약)."
  echo "         실제 실행: RUN_COST_CHECK=true bash $(basename "${BASH_SOURCE[0]}")"
elif command -v infracost >/dev/null 2>&1; then
  FINOPS_FIXTURES="$TESTS_DIR/fixtures-finops"

  out=$(cd "$FINOPS_FIXTURES/ok-baseline" && infracost breakdown --path . 2>&1) || true
  if grep -E -qi "$PFC_EXTENDED_SUPPORT_PATTERN" <<<"$out"; then
    report "ok-baseline (Extended Support 없음)" 1 "기대: 매치 없음 / 실제: 매치됨"
  else
    report "ok-baseline (Extended Support 없음)" 0
  fi

  out=$(cd "$FINOPS_FIXTURES/fail-extended-support" && infracost breakdown --path . 2>&1) || true
  if grep -E -qi "$PFC_EXTENDED_SUPPORT_PATTERN" <<<"$out"; then
    report "fail-extended-support (Extended Support 비용 감지)" 0
  else
    report "fail-extended-support (Extended Support 비용 감지)" 1 "기대: 매치 / 실제: 매치 없음 (AWS 가격 정책이 바뀌었을 수 있습니다)"
  fi

  # 3. validate_finops_costs()가 trap ... RETURN 으로 임시파일을 정리했었는데, bash에서
  #    trap RETURN은 함수 스코프가 아니라 프로세스 전역이라 이 함수가 끝난 뒤에도 남아
  #    있다가 이후 리턴되는 다른 함수(요약 로그 등)에서 발동해 이미 스코프를 벗어난
  #    $cost_output_tmp를 참조하며 "unbound variable"로 죽었다. RUN_COST_CHECK=true
  #    실제 커밋 경로에서만 재현되고, infracost를 직접 호출하는 위 1/2번 케이스는 이
  #    함수 자체를 거치지 않아 못 잡는다. pre-flight-check.sh 전체를 실제로 돌려서
  #    이 함수 뒤에도 파이프라인이 안 죽고 끝까지 완주하는지를 고정한다.
  #    (이 테스트는 실제 인프라 정합성이 아니라 "파이프라인이 안 죽고 끝까지 도는지"만
  #    확인하면 된다. checkov도 통과하는 aws 스킬의 ok-baseline[보안 그룹 등 실제 aws
  #    provider 필요]을 쓰면 terraform init이 매번 새 mktemp 디렉토리에서 AWS
  #    provider를 새로 받느라 느리다. provider 선언이 아예 없는 최소 tf 파일은
  #    terraform init이 훨씬 빠르게 끝나고, 리소스가 없으니 checkov/tflint도 그냥
  #    통과한다 — 같은 검증 목적을 훨씬 빠르게 만족시킨다.)
  E2E_REPO=$(mktemp -d)
  trap 'rm -rf "$E2E_REPO"' EXIT
  git -C "$E2E_REPO" init -q
  cat >"$E2E_REPO/main.tf" <<'TF'
terraform {
  required_version = "~> 1.5"
}
TF
  git -C "$E2E_REPO" add main.tf
  CODE=0
  OUT=$( (cd "$E2E_REPO" && QUIET=0 RUN_COST_CHECK=true bash "$REPO_ROOT/bin/hooks/pre-flight-check.sh") 2>&1) || CODE=$?
  if [ "$CODE" -eq 0 ] && ! grep -qF "unbound variable" <<<"$OUT" && grep -qF "All Pre-Flight Checks Passed Successfully" <<<"$OUT"; then
    report "validate_finops_costs 이후 파이프라인 완주 (trap 전역 누수 없음)" 0
  else
    report "validate_finops_costs 이후 파이프라인 완주 (trap 전역 누수 없음)" 1 "exit=$CODE / $(tail -3 <<<"$OUT" | tr '\n' ' ')"
  fi
else
  report "infracost CLI" 1 "도구 미설치 — 'mise install' 후 다시 실행하십시오"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
