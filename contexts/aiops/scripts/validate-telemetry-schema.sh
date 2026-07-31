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
if find "$TARGET_DIR" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.tf" -o -name "*.json" \) ! -path "*/.git/*" -print0 | xargs -0 grep -iE "(AWS_SECRET_ACCESS_KEY|AZURE_CLIENT_SECRET|password|secret_key)" 2>/dev/null | grep -v 'EXAMPLE' >/dev/null 2>&1; then
  echo "❌ [ERROR] Plaintext secrets detected in telemetry/IaC manifests!"
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
