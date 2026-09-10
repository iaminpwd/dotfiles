#!/usr/bin/env bash
# 원본과 설치 상태가 다르면 검증기가 실패하는지 격리된 홈에서 확인한다.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PYTHON=$(mise which python3)
FAKE="$TMP/home"
REPO="$TMP/source"
mkdir -p "$REPO/.github/scripts"
cp "$ROOT/.github/scripts/verify-bootstrap-env.sh" "$REPO/.github/scripts/"

build_home() {
  "$PYTHON" - "$REPO" "$FAKE" "$PYTHON" <<'PY'
import json
from pathlib import Path
import shutil
import sys
r, h = map(Path, sys.argv[1:3])
shutil.rmtree(h, ignore_errors=True)
h.mkdir()
for rel in ['stow/zsh/.zshrc', 'contexts/base.AGENTS.md', 'contexts/dotfiles/SKILL.md',
            'contexts/aws/SKILL.md', 'contexts/k8s/SKILL.md',
            'contexts/aws/references/core.md', 'bin/hooks/agent-edits-hook.sh',
            'bin/hooks/pre-flight-gate-hook.sh']:
    p = r / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('fixture\n')
    if p.suffix == '.sh':
        p.chmod(0o755)
def link(target, source):
    target.parent.mkdir(parents=True, exist_ok=True)
    target.unlink(missing_ok=True)
    target.symlink_to(source)
link(h / '.zshrc', r / 'stow/zsh/.zshrc')
for parent, name in [('.gemini/config', 'AGENTS.md'), ('.claude', 'CLAUDE.md'), ('.codex', 'AGENTS.md')]:
    link(h / parent / name, r / 'contexts/base.AGENTS.md')
for skill in ['aws', 'k8s']:
    for parent in ['.gemini/config', '.claude', '.agents']:
        link(h / parent / 'skills' / skill / 'SKILL.md', r / 'contexts' / skill / 'SKILL.md')
        if skill == 'aws':
            link(h / parent / 'skills' / skill / 'references', r / 'contexts/aws/references')
for name in ['AGENTS.md', 'CLAUDE.md']:
    link(r / name, r / 'contexts/dotfiles/SKILL.md')
for name in ['agent-edits-hook.sh', 'pre-flight-gate-hook.sh']:
    link(h / '.local/bin' / name, r / 'bin/hooks' / name)
link(h / '.local/bin/python3', Path(sys.argv[3]))
p = h / '.local/bin/mise'
p.write_text('#!/bin/sh\nexit 0\n')
p.chmod(0o755)
p = h / '.zshrc.local'
p.write_text('# fixture\n')
p.chmod(0o600)
def group(name):
    return [{'hooks': [{'command': str(r / 'bin/hooks' / name)}]}]
(h / '.claude/settings.json').write_text(json.dumps({'hooks': {
    'PostToolUse': group('agent-edits-hook.sh'), 'Stop': group('pre-flight-gate-hook.sh')}}))
(h / '.gemini/config/hooks.json').write_text(json.dumps({'agent-edits-log': {
    'PostToolUse': group('agent-edits-hook.sh')}}))
PY
}
run_sut() {
  HOME="$FAKE" bash "$REPO/.github/scripts/verify-bootstrap-env.sh" >"$TMP/out" 2>&1
}
failures=0
for case in complete wrong-link missing-rule missing-skill missing-asset missing-script missing-hook unsafe-mode missing-tool; do
  build_home
  case "$case" in
  wrong-link) ln -sf "$REPO/contexts/base.AGENTS.md" "$FAKE/.zshrc" ;;
  missing-rule) rm "$FAKE/.codex/AGENTS.md" ;;
  missing-skill) rm "$FAKE/.agents/skills/k8s/SKILL.md" ;;
  missing-asset) rm "$FAKE/.claude/skills/aws/references" ;;
  missing-script) rm "$FAKE/.local/bin/agent-edits-hook.sh" ;;
  missing-hook) echo '{}' >"$FAKE/.claude/settings.json" ;;
  unsafe-mode) chmod 644 "$FAKE/.zshrc.local" ;;
  missing-tool) printf '#!/bin/sh\nexit 1\n' >"$FAKE/.local/bin/mise" ;;
  esac
  rc=0
  run_sut || rc=$?
  if { [ "$case" = complete ] && [ "$rc" = 0 ]; } || { [ "$case" != complete ] && [ "$rc" != 0 ]; }; then
    echo "PASS: $case"
  else
    echo "FAIL: $case"
    cat "$TMP/out"
    failures=$((failures + 1))
  fi
done
[ "$failures" = 0 ]
