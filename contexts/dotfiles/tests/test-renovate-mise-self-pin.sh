#!/usr/bin/env bash
# install-mise.sh의 mise 자체 버전 pin이 Renovate 자동 업데이트 대상인지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1])
installer = (root / "bin/utils/install-mise.sh").read_text()
config = json.loads((root / ".github/renovate.json").read_text())

m = re.search(r'^MISE_VERSION="(?P<version>[0-9]+\.[0-9]+\.[0-9]+)"$', installer, re.M)
if not m:
    raise AssertionError("install-mise.sh의 고정 MISE_VERSION을 찾지 못했습니다")
pinned = m.group("version")

matching = []
for manager in config.get("customManagers", []):
    if manager.get("customType") != "regex":
        continue
    patterns = manager.get("managerFilePatterns", [])
    if "bin/utils/install-mise.sh" not in patterns:
        continue
    for expr in manager.get("matchStrings", []):
        try:
            found = re.search(expr, installer)
        except re.error as exc:
            raise AssertionError(f"mise Renovate regex가 유효하지 않습니다: {exc}") from exc
        if found and found.groupdict().get("currentValue") == pinned:
            matching.append(manager)
            break

if not matching:
    raise AssertionError(
        "MISE_VERSION pin이 Renovate custom manager에 등록되지 않아 mise 자체 업데이트가 자동 추적되지 않습니다"
    )

manager = matching[0]
if manager.get("datasourceTemplate") != "github-releases":
    raise AssertionError("mise 자체 pin은 jdx/mise GitHub Release를 추적해야 합니다")
if manager.get("packageNameTemplate") != "jdx/mise":
    raise AssertionError("mise Renovate manager의 packageNameTemplate은 jdx/mise여야 합니다")
extract = manager.get("extractVersionTemplate", "")
if "(?<version>" not in extract or not extract.startswith("^v"):
    raise AssertionError("GitHub release의 v prefix를 MISE_VERSION 형식으로 제거하는 extractVersionTemplate이 필요합니다")

print(f"PASS: mise {pinned} self-pin is Renovate-managed")
PY
