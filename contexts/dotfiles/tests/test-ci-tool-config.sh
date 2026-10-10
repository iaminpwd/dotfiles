#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
python3 - "$ROOT" <<'PY'
import importlib.util
from pathlib import Path
import sys
import tomllib
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('ci_tools', root / '.github/scripts/ci-tool-config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = (root / 'stow/mise/.config/mise/config.toml').read_text()
original = tomllib.loads(source)['tools']
selected = tomllib.loads(module.render(source))['tools']
assert selected and len(selected) < len(original)
assert all(original[k] == v for k, v in selected.items())
print('PASS: 축소된 설정에 정본 버전 유지')
changed = source.replace('"'+original['shellcheck']+'"', '"99.0.0"')
assert tomllib.loads(module.render(changed))['tools']['shellcheck'] == '99.0.0'
print('PASS: 정본 버전 변경 자동 반영')
try:
    module.render('[tools]\nshellcheck="1.0"\n')
except KeyError:
    print('PASS: 필수 도구 정의 누락 시 실패')
else:
    raise AssertionError('missing tools accepted')
# 동적 도구 탐색부에서 쓰는 도구는 CI 설정에서 빠지면 안 된다.
import re
aliases = {'ansible-playbook': 'ansible', 'ansible-lint': 'pipx:ansible-lint',
           'yamllint': 'pipx:yamllint', 'sam': 'pipx:aws-sam-cli'}
for pattern in ('bin/lib/pfc-*.sh', 'bin/hooks/plugins/*.sh', 'contexts/*/tests/*.sh'):
    for path in root.glob(pattern):
        for tool in re.findall(r'\b(?:has_tool|require_tool|tf_require_tool) ([a-z][a-z0-9-]*)', path.read_text()):
            key = aliases.get(tool, tool)
            if key in original:
                assert key in selected, (path, tool)
print('PASS: 검사기와 회귀 테스트의 도구 탐색 대상 유지')
# CI must exercise the domain validators too. The pre-flight gate intentionally
# leaves them opt-in for fast local execution; an unqualified CI verify would
# silently skip Terraform, Helm, K8s, conftest and delegated domain policies.
workflow = (root / '.github/workflows/ci.yml').read_text()
assert 'RUN_SUITE_PFC_DOMAIN_CHECKS=1 PFC_PROFILE=full just verify' in workflow, (
    'CI verify must enable the domain policy validators')
print('PASS: CI 전체 Verify에서 도메인 정책 검사 활성화')
print(f'설치 대상: {len(original)} -> {len(selected)}')
PY
