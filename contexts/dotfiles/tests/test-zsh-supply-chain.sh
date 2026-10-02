#!/usr/bin/env bash
# 외부 Git 소스가 태그/브랜치가 아니라 불변 commit SHA로 고정되는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1])
tasks_path = root / "ansible/roles/zsh/tasks/main.yml"
renovate_path = root / ".github/renovate.json"

tasks = tasks_path.read_text()
deps = re.findall(
    r"repo: 'https://github\.com/([^']+)\.git'\n"
    r"\s+dest:.*\n"
    r"\s+depth: 1\n"
    r"\s+version: ([^\s#]+)(?:\s+#\s*(\S+))?",
    tasks,
)
if len(deps) != 3:
    raise AssertionError(f"expected 3 zsh git dependencies, found {len(deps)}: {deps!r}")

for repo_name, revision, tag in deps:
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise AssertionError(
            f"{repo_name}: mutable git ref is not allowed for executable shell code: {revision}"
        )
    print(f"PASS: {repo_name} pinned to immutable commit {revision[:12]}")

plugins = {
    "zsh-users/zsh-autosuggestions",
    "zsh-users/zsh-syntax-highlighting",
}
for repo_name, revision, tag in deps:
    if repo_name in plugins:
        if not tag or not re.fullmatch(r"v?\d+(?:\.\d+)+", tag):
            raise AssertionError(
                f"{repo_name}: pinned digest must retain its release tag comment for Renovate"
            )

config = json.loads(renovate_path.read_text())
found = set()
for manager in config.get("customManagers", []):
    if manager.get("datasourceTemplate") != "github-tags":
        continue
    joined = "\n".join(manager.get("matchStrings", []))
    for plugin in plugins:
        if plugin in joined.replace("\\/", "/") or plugin.replace("/", "\\/") in joined:
            if "currentDigest" not in joined or "currentValue" not in joined:
                raise AssertionError(
                    f"{plugin}: Renovate manager must track both release tag and immutable digest"
                )
            found.add(plugin)

missing = plugins - found
if missing:
    raise AssertionError(f"missing digest-aware Renovate manager(s): {sorted(missing)}")

print("PASS: Renovate keeps plugin release tags while updating immutable digests")
PY
