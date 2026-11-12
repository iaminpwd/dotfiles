#!/usr/bin/env bash
# Renovate의 mise 도구 업데이트 정책을 검증한다:
# patch만 그룹 PR + CI 통과 시 automerge, minor/major는 도구별 개별 PR(automerge 없음).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
config = json.loads((root / ".github/renovate.json").read_text())
rules = config.get("packageRules", [])


def fail(msg):
    raise AssertionError(msg)


# 기존 전역 정책(스케줄·취약점 알림·Actions digest pin) 보존
if config.get("schedule") != ["before 6am on monday"]:
    fail("주간 스케줄(before 6am on monday)이 유지되어야 합니다")
if config.get("osvVulnerabilityAlerts") is not True:
    fail("osvVulnerabilityAlerts가 유지되어야 합니다")
if "helpers:pinGitHubActionDigests" not in config.get("extends", []):
    fail("GitHub Actions digest pin preset이 유지되어야 합니다")
if config.get("automerge") or config.get("platformAutomerge"):
    fail("automerge는 전역이 아니라 mise patch 규칙에만 한정되어야 합니다")

mise_rules = [r for r in rules if r.get("matchManagers") == ["mise"]]


def applies_to(rule, update_type):
    types = rule.get("matchUpdateTypes")
    return types is None or update_type in types


for rule in mise_rules:
    for update_type in ("minor", "major"):
        if applies_to(rule, update_type) and rule.get("groupName"):
            fail(f"mise {update_type} 업데이트가 그룹으로 묶이면 안 됩니다: {rule.get('groupName')}")
        if applies_to(rule, update_type) and rule.get("automerge"):
            fail(f"mise {update_type} 업데이트는 automerge하면 안 됩니다")

base = [r for r in mise_rules if "matchUpdateTypes" not in r and "matchDepNames" not in r]
if len(base) != 1:
    fail("mise 공통 분류 규칙이 정확히 하나여야 합니다")
if not {"dependencies", "mise"} <= set(base[0].get("labels", [])):
    fail("mise 도구 PR은 dependencies/mise 라벨을 유지해야 합니다")
if base[0].get("separateMinorPatch") is not True:
    fail("patch와 minor가 함께 나와도 patch를 분리하도록 separateMinorPatch가 필요합니다")

patch = [r for r in mise_rules if r.get("matchUpdateTypes") == ["patch"]]
if len(patch) != 1:
    fail("mise patch 전용 규칙이 정확히 하나여야 합니다")
patch = patch[0]
if not patch.get("groupName"):
    fail("mise patch 업데이트는 하나의 그룹 PR로 묶여야 합니다")
if patch.get("automerge") is not True:
    fail("mise patch 그룹은 CI 통과 시 automerge되어야 합니다")
# ci.yml은 PR에서만 CI가 돌므로 branch 방식이면 체크가 없다.
if patch.get("automergeType") != "pr":
    fail("CI가 pull_request 트리거에서만 돌므로 automergeType은 pr이어야 합니다")
# main에 필수 체크가 없으므로 GitHub 네이티브 auto-merge 대신 Renovate가 체크를 확인하고 머지한다.
if patch.get("platformAutomerge") is not False:
    fail("필수 체크가 없는 main에서는 platformAutomerge를 끄고 Renovate가 상태 체크를 확인해야 합니다")
if patch.get("ignoreTests"):
    fail("CI 결과를 무시하는 ignoreTests는 금지입니다")

# aqua github_release datasource 오버라이드 규칙 보존
if not any(r.get("overrideDatasource") == "github-releases" for r in mise_rules):
    fail("aqua github_release 도구의 github-releases datasource 오버라이드가 유지되어야 합니다")

print("PASS: mise patch updates are grouped+automerged, minor/major stay per-tool manual PRs")
PY
