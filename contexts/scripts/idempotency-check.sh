#!/usr/bin/env bash
# idempotency-check.sh
# Check if shell scripts use append without state checking

set -euo pipefail

FILES=("$@")

if [ ${#FILES[@]} -eq 0 ]; then
  exit 0
fi

for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || continue
  if grep -qE ">>|tee -a" "$FILE"; then
    if ! grep -qE "(grep -q|if \[|if test)" "$FILE"; then
      echo "⚠️ [WARNING] Idempotency check: '$FILE' uses append (>> or tee -a) but lacks state checking logic (e.g., grep -q or if [ ... ]). Consider adding idempotency guards." >&2
    fi
  fi
done

exit 0
