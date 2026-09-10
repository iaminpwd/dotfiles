#!/usr/bin/env bash
# 설치 결과를 원본의 파일·스킬·훅 선언과 대조한다. 값을 출력하지 않는다.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
for tool in shellcheck just ansible-playbook jq terraform; do
  mise which "$tool" >/dev/null
done
python3 - "$ROOT" "$HOME" <<'PY'
import json
from pathlib import Path
import stat
import sys

root, home = map(Path, sys.argv[1:])


def require(ok, message):
    if not ok:
        sys.exit(f"[ERROR] {message}")


def link(target, source):
    require(target.is_symlink() and target.exists() and target.resolve() == source.resolve(),
            f"링크 대상 불일치: {target}")


for package in (root / 'stow').iterdir():
    if package.is_dir():
        for source in package.rglob('*'):
            if source.is_file():
                link(home / source.relative_to(package), source)
for parent, name in [('.gemini/config', 'AGENTS.md'), ('.claude', 'CLAUDE.md'),
                     ('.codex', 'AGENTS.md')]:
    link(home / parent / name, root / 'contexts/base.AGENTS.md')
for skill in (root / 'contexts').iterdir():
    if skill.name.startswith('.') or skill.name == 'dotfiles' or not skill.is_dir():
        continue
    for asset in ['SKILL.md', 'references', 'scripts', 'examples']:
        source = skill / asset
        if source.exists():
            for parent in ['.gemini/config', '.claude', '.agents']:
                link(home / parent / 'skills' / skill.name / asset, source)
for base in [root / 'bin', root / 'contexts']:
    for source in base.rglob('*.sh'):
        relative = source.relative_to(root)
        if any(p.startswith('.') for p in relative.parts):
            continue
        if ('bin' in relative.parts or 'scripts' in relative.parts) and source.stat().st_mode & stat.S_IXUSR:
            link(home / '.local/bin' / source.name, source)
for name in ['AGENTS.md', 'CLAUDE.md']:
    link(root / name, root / 'contexts/dotfiles/SKILL.md')
local = home / '.zshrc.local'
require(local.is_file() and stat.S_IMODE(local.stat().st_mode) == 0o600,
        f"시크릿 파일 권한은 0600이어야 합니다: {local}")
claude = json.loads((home / '.claude/settings.json').read_text())
gemini = json.loads((home / '.gemini/config/hooks.json').read_text())
for settings, event, script in [
    (claude.get('hooks', {}), 'PostToolUse', 'agent-edits-hook.sh'),
    (claude.get('hooks', {}), 'Stop', 'pre-flight-gate-hook.sh'),
    (gemini.get('agent-edits-log', {}), 'PostToolUse', 'agent-edits-hook.sh'),
]:
    commands = [h.get('command') for group in settings.get(event, []) for h in group.get('hooks', [])]
    require(str((root / 'bin/hooks' / script).resolve()) in commands, f"필수 훅 누락: {event}/{script}")
print('[OK] 설치 도구·링크·스킬·훅·시크릿 파일 권한 확인')
PY
