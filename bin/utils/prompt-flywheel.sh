#!/usr/bin/env bash
set -euo pipefail

echo "🔍 [Prompt Quality Flywheel] Analyzing recent history..."
echo "------------------------------------------------"

EDITS_LOG=".agent-state/edits.log"
if [ ! -f "$EDITS_LOG" ]; then
  echo "❌ No edits.log found at $EDITS_LOG"
  exit 1
fi

echo "🚨 Recent 20 Log Entries:"
tail -20 "$EDITS_LOG"
echo "------------------------------------------------"
echo "💡 AI Agent Instructions for Flywheel:"
echo "1. Analyze the logs above to identify which rule/prompt caused the failure."
echo "2. Use your tools (grep_search, view_file) to check the current text of the referenced rule."
echo "3. If the rule still has the flaw that caused this issue, generate a <loss_analysis> block."
echo "4. Propose a concrete revision to the prompt/rulebook."
