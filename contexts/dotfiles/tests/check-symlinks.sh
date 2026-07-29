#!/usr/bin/env bash
# check-symlinks.sh

set -euo pipefail

echo "Running broken-symlink-detector..."
bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/broken-symlink-detector.sh"
