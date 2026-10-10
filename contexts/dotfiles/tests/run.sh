#!/usr/bin/env bash
# Per-domain wrapper: standalone regressions are discovered by filename.
# The shared runner preserves fail-all reporting and optional CI timings.
set -euo pipefail
export QUIET=0
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
exec bash "$ROOT/tests/lib/run-domain-tests.sh" "$TESTS_DIR" "$@"
