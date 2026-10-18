#!/usr/bin/env bash
# AI Stop -> run-suite -> pre-flight Terraform 경로의 격리된 계약 테스트.
# 실제 terraform init이나 클라우드 API를 호출하지 않고 CLI 스텁의 인자/종료 코드를 확인한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
TOOLS="$TMP/tools"
mkdir -p "$REPO/bin/hooks" "$REPO/bin/lib" "$REPO/infra/app one" "$REPO/infra/other" "$TOOLS"
cp "$ROOT/bin/hooks/pre-flight-check.sh" "$REPO/bin/hooks/"
cp "$ROOT/bin/lib/"{script-init,tool-probe,pfc-iac-checks,pfc-quality-checks,plugin-targets}.sh "$REPO/bin/lib/"
ln -s bin/hooks/pre-flight-check.sh "$REPO/pre-flight-check.sh"

cat >"$TOOLS/terraform" <<'EOF'
#!/usr/bin/env bash
printf 'terraform|%s\n' "$*" >>"$TF_STOP_TRACE"
if [ "${TF_STOP_FAIL:-}" = terraform ] && [[ " $* " == *' validate'* ]]; then exit 4; fi
EOF
cat >"$TOOLS/tflint" <<'EOF'
#!/usr/bin/env bash
printf 'tflint|%s\n' "$*" >>"$TF_STOP_TRACE"
if [ "${TF_STOP_FAIL:-}" = tflint ] && [[ " $* " != *' --init'* ]]; then exit 4; fi
EOF
cat >"$TOOLS/checkov" <<'EOF'
#!/usr/bin/env bash
printf 'checkov|%s\n' "$*" >>"$TF_STOP_TRACE"
if [ "${TF_STOP_FAIL:-}" = checkov ]; then exit 4; fi
EOF
chmod +x "$TOOLS/"*
export PATH="$TOOLS:/usr/bin:/bin"
export TF_STOP_TRACE="$TMP/trace"
PFC="$REPO/bin/hooks/pre-flight-check.sh"
STOP="$ROOT/bin/hooks/pre-flight-gate-hook.sh"

git -C "$REPO" init -q
git -C "$REPO" config user.name Fixture
git -C "$REPO" config user.email fixture@example.invalid
printf 'terraform { required_version = ">= 1.0" }\n' >"$REPO/infra/app one/main.tf"
printf 'terraform { required_version = ">= 1.0" }\n' >"$REPO/infra/other/main.tf"
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm initial

expect_trace() {
  local pattern=$1
  if ! grep -qF -- "$pattern" "$TF_STOP_TRACE"; then
    echo "FAIL: expected trace '$pattern': $(cat "$TF_STOP_TRACE")" >&2
    exit 1
  fi
}

# idempotency:bypass — 격리된 fixture의 최초 Git 변경분을 만드는 테스트 전용 append.
printf '# changed\n' >>"$REPO/infra/app one/main.tf"
: >"$TF_STOP_TRACE"
(cd "$REPO" && PFC_PROFILE=stop bash "$PFC" --changed)
expect_trace 'terraform|fmt -check infra/app one/main.tf'
expect_trace 'terraform|-chdir=infra/app one validate'
expect_trace 'tflint|--chdir=infra/app one'
expect_trace 'checkov|--directory infra/app one'
if grep -qF 'infra/other' "$TF_STOP_TRACE"; then
  echo 'FAIL: Stop scanned an unchanged Terraform root' >&2
  exit 1
fi
echo 'PASS: 변경된 Terraform root만 fmt/validate/TFLint/Checkov 검사'

for failure in terraform tflint checkov; do
  if (cd "$REPO" && TF_STOP_FAIL="$failure" PFC_PROFILE=stop bash "$PFC" --changed >/dev/null 2>&1); then
    echo "FAIL: $failure failure was accepted" >&2
    exit 1
  fi
done
echo 'PASS: terraform validate / TFLint / Checkov 실패 전파'

# 테스트 환경의 PATH에서 검사기만 제거해 미설치 시의 무검증 통과 여부를 확인한다.
mv "$TOOLS/tflint" "$TMP/tflint-disabled"
if (cd "$REPO" && PFC_PROFILE=stop bash "$PFC" --changed >/dev/null 2>&1); then
  echo 'FAIL: missing TFLint accepted' >&2
  exit 1
fi
mv "$TMP/tflint-disabled" "$TOOLS/tflint"
mv "$TOOLS/checkov" "$TMP/checkov-disabled"
if (cd "$REPO" && PFC_PROFILE=stop bash "$PFC" --changed >/dev/null 2>&1); then
  echo 'FAIL: missing Checkov accepted' >&2
  exit 1
fi
mv "$TMP/checkov-disabled" "$TOOLS/checkov"
echo 'PASS: 필수 검사 도구 미설치는 Stop 실패'

git -C "$REPO" checkout -- 'infra/app one/main.tf'
printf 'environment = "test"\n' >"$REPO/infra/app one/test.tfvars"
: >"$TF_STOP_TRACE"
(cd "$REPO" && PFC_PROFILE=stop bash "$PFC" --changed)
expect_trace 'tflint|--chdir=infra/app one'
expect_trace 'checkov|--directory infra/app one'
echo 'PASS: tfvars-only 수정도 해당 Terraform root 재검사'

git -C "$REPO" add 'infra/app one/test.tfvars'
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm 'add tfvars'
printf 'docs\n' >"$REPO/README.md"
: >"$TF_STOP_TRACE"
(cd "$REPO" && PFC_PROFILE=stop bash "$PFC" --changed)
[ ! -s "$TF_STOP_TRACE" ]
echo 'PASS: 비Terraform 변경에는 심층 검사 생략'

git -C "$REPO" add README.md
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm docs
# idempotency:bypass — Stop 실제 실행을 위한 fixture 변경분.
printf '# changed again\n' >>"$REPO/infra/app one/main.tf"
: >"$TF_STOP_TRACE"
payload=$(printf '{"cwd":"%s","stop_hook_active":false}' "$REPO")
output=$(printf '%s' "$payload" | bash "$STOP")
expect_trace 'checkov|--directory infra/app one'
if ! grep -qF 'additionalContext' <<<"$output" || grep -qF '"decision": "block"' <<<"$output"; then
  echo "FAIL: successful Stop contract: $output" >&2
  exit 1
fi
echo 'PASS: 실제 Stop → run-suite → TFLint/Checkov 연결'

: >"$TF_STOP_TRACE"
cached=$(printf '%s' "$payload" | bash "$STOP")
[ -z "$cached" ] && [ ! -s "$TF_STOP_TRACE" ]
echo 'PASS: 동일한 성공 변경은 캐시 재사용'

# idempotency:bypass — 성공 캐시 무효화를 검증하기 위한 fixture 변경분.
printf '# another change\n' >>"$REPO/infra/app one/main.tf"
if ! output=$(printf '%s' "$payload" | TF_STOP_FAIL=checkov bash "$STOP"); then
  echo 'FAIL: Stop hook process returned nonzero instead of protocol JSON' >&2
  exit 1
fi
if ! grep -qF '"decision": "block"' <<<"$output" || ! grep -qF 'Checkov Terraform 검사 실패' <<<"$output"; then
  echo "FAIL: Stop did not block on Checkov failure: $output" >&2
  exit 1
fi
: >"$TF_STOP_TRACE"
output=$(printf '%s' "$payload" | bash "$STOP")
expect_trace 'checkov|--directory infra/app one'
echo 'PASS: 실패를 AI에 전달하고 변경 재검사 (실패 캐시 없음)'
