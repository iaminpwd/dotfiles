#!/usr/bin/env bash
# Unit Test Suite for aiops skill
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== [AIOps Unit Test] Running Telemetry Validator ==="
bash "$SKILL_ROOT/scripts/validate-telemetry-schema.sh" "$SKILL_ROOT"

echo "=== [AIOps Unit Test] Running Anomaly Threshold Evaluator ==="
python3 "$SKILL_ROOT/scripts/eval-anomaly-threshold.py"

echo "=== [AIOps Unit Test] Running Incident RAG Pipeline Example ==="
python3 "$SKILL_ROOT/examples/anomaly-rag-pipeline.py"

echo "✅ [AIOps Unit Test] All AIOps tests passed successfully."
