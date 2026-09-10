#!/usr/bin/env python3
"""검증 CI용 mise 설정을 생성한다. 버전은 개인 환경 설정을 공유한다."""
import json
from pathlib import Path
import sys
import tomllib

# 검증기·회귀 테스트 및 설치 백엔드가 사용하는 도구만 유지한다.
TOOLS = (
    'python', 'uv', 'pipx', 'just', 'jq', 'fzf',
    'shellcheck', 'shfmt', 'pipx:yamllint',
    'terraform', 'tflint', 'checkov', 'ansible', 'pipx:ansible-lint',
    'pipx:aws-sam-cli', 'infracost',
    'trivy', 'trufflehog', 'conftest', 'hadolint',
    'kubectl', 'helm', 'kube-linter', 'kyverno', 'pluto', 'promtool', 'yq',
)


def render(source):
    config = tomllib.loads(source)
    tools = config['tools']
    # 누락된 이름은 오류로 종료해 버전 변경이나 이름 변경을 조용히 무시하지 않는다.
    selected = {name: tools[name] for name in TOOLS}
    if not all(isinstance(version, str) for version in selected.values()):
        raise ValueError('CI 도구 버전은 문자열이어야 합니다')
    return '[tools]\n' + ''.join(
        f'{json.dumps(name)} = {json.dumps(version)}\n'
        for name, version in selected.items()
    )


if __name__ == '__main__':
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        Path(__file__).resolve().parents[2] / 'stow/mise/.config/mise/config.toml'
    )
    print(render(source.read_text()), end='')
