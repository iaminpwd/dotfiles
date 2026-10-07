#!/usr/bin/env bash
set -euo pipefail

# idempotency:bypass
echo "intentional one-shot append" >> /tmp/idempotency-bypass.log
