#!/usr/bin/env bash
# Telemetry Schema & Pipeline Manifest Validator for AIOps
set -euo pipefail

echo "=========================================================="
echo "🔍 [AIOps-Preflight] Telemetry Pipeline & Manifest Validator"
echo "=========================================================="

TARGET_DIR="${1:-.}"

errors=0

# 1. Yaml & Schema syntax check
if command -v yamllint >/dev/null 2>&1; then
  echo "▶ Yamllint running on telemetry manifests..."
  find "$TARGET_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "*/.git/*" | while read -r file; do
    if ! yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "$file" >/dev/null 2>&1; then
      echo "⚠️ [WARN] Yaml formatting issues in $file"
    fi
  done
fi

# 2. Check for unmasked PII / credentials in manifests
echo "▶ Checking for plaintext secrets in manifests..."
# Target manifest & code files only (excluding markdown documentation examples)
# 키워드 뒤에 ':'/'=' 대입이 바로 오는 경우만 매치한다. 그렇지 않으면 값 자체가 아니라
# 필드/변수 이름일 뿐인 password_policy, secret_key_rotation_enabled,
# variable "db_password" {} 같은 무해한 식별자까지 걸려 실제 커밋을 차단하는 오탐이 난다.
# -H: 대상이 파일 1개일 때도 파일명을 붙여 위치를 항상 특정할 수 있게 한다.
# -n: 줄 번호. 예전에는 결과를 통째로 >/dev/null 로 버려서, 차단은 되는데 "어느 파일
# 어느 줄이 문제인지"를 전혀 알려주지 않았다. 하드 블록이 고칠 대상을 못 알려주면
# 사용자는 우회밖에 할 수 없다.
SECRET_HITS=$(find "$TARGET_DIR" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.tf" -o -name "*.json" \) ! -path "*/.git/*" -print0 |
  xargs -0 grep -HinE "(AWS_SECRET_ACCESS_KEY|AZURE_CLIENT_SECRET|password|secret_key)\s*[:=]" 2>/dev/null |
  grep -v 'EXAMPLE' || true)

if [ -n "$SECRET_HITS" ]; then
  echo "❌ [ERROR] Plaintext secrets detected in telemetry/IaC manifests!"
  # 위치(파일:줄)만 출력하고 매치된 줄의 내용은 절대 찍지 않는다. 여기 걸린 값은 정의상
  # 시크릿 후보라, 원문을 그대로 출력하면 이 스크립트가 도는 모든 로그·CI 출력·AI 컨텍스트에
  # 시크릿을 퍼뜨리게 된다(base.AGENTS.md 7장 Sensitive Data Masking).
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    printf '   - %s\n' "$(printf '%s' "$hit" | cut -d: -f1,2)"
  done <<<"$SECRET_HITS"
  errors=$((errors + 1))
else
  echo "✅ No hardcoded secrets found in telemetry manifests."
fi

# 3. Check for ISMS-P Audit Marker or Closed-Loop Spec presence
echo "▶ Verifying AIOps Guardrail Markers..."
if grep -rn "ClosedLoopPolicy" "$TARGET_DIR" --exclude-dir=".git" >/dev/null 2>&1; then
  echo "✅ ClosedLoopPolicy manifest validated."
else
  echo "ℹ️ [INFO] No explicit ClosedLoopPolicy manifest in $TARGET_DIR (Skipped)"
fi

if [ "$errors" -gt 0 ]; then
  echo "----------------------------------------------------------"
  echo "❌ Telemetry schema validation failed with $errors error(s)."
  exit 1
fi

echo "=========================================================="
echo "✅ Telemetry Validation Completed Successfully."
echo "=========================================================="
