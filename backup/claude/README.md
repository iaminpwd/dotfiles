# Claude Code 설정 백업

Claude Code 전역 설정 사본이다. Stow는 이 폴더를 읽지 않는다.

| 파일 | 원본 위치 | 비고 |
|---|---|---|
| `settings.json` | Linux·macOS·WSL `~/.claude/settings.json` | hook은 빼고 둔다(`bin/utils/merge-agent-hooks.sh`가 넣는다) |
| `settings.windows.json` | Windows `%USERPROFILE%\.claude\settings.json` | hook 없음 |

- 전역 지침(`CLAUDE.md`)은 백업이 아니라 원본이 `contexts/base.AGENTS.md`다. WSL은 Ansible이 링크하고, Windows는 이 파일을 `%USERPROFILE%\.claude\CLAUDE.md`로 복사해서 쓴다.
- `settings.json`은 Claude Code가 직접 고쳐 쓰므로 링크하지 않는다. `bootstrap.sh`(Ansible `ai_agent` 역할)가 `~/.claude/settings.json`이 **없을 때만** 이 사본을 복사한다. 이미 있는 파일은 덮어쓰지 않는다. 그다음 같은 역할의 `merge-agent-hooks.sh`가 hook을 넣는다.
- 쓰던 컴퓨터에서 설정을 바꾸면 hook을 뺀 내용을 여기에 다시 복사해 커밋한다(`jq 'del(.hooks)' ~/.claude/settings.json > backup/claude/settings.json`).
- `bootstrap.sh`는 Windows를 지원하지 않는다. Windows에서는 `settings.windows.json`과 `contexts/base.AGENTS.md`를 `%USERPROFILE%\.claude\`의 `settings.json`, `CLAUDE.md`로 직접 복사한다.
- 모델은 버전 없는 별칭(`fable`, `opus`)으로 둔다. 새 버전이 나와도 고칠 필요가 없다.
