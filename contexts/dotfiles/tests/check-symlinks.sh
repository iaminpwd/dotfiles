#!/usr/bin/env bash
# check-symlinks.sh

set -euo pipefail

echo "Running broken-symlink-detector..."
broken-symlink-detector.sh
