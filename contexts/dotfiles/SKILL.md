---
name: dotfiles
description: |
  이 저장소의 bootstrap, Ansible, Stow, mise, shell 설정, hooks와 회귀 검증을 변경할 때 사용하는 로컬 스킬.
---
# Dotfiles 로컬 작업 지침

- 루트 `AGENTS.md`·`CLAUDE.md`는 이 파일을 가리킨다. 글로벌 스킬로 중복 등록하지 않는다.
- 설정 원본은 `stow/`, 도구 버전 원본은 `stow/mise/.config/mise/config.toml`이다. 설치는 `bootstrap.sh`·`ansible/`, 검사·훅은 `bin/`에 있다.
- 심볼릭 링크의 실제 원본을 확인하고 기존 사용자 파일·설정·시크릿을 보존한다. 배포·등록 경로를 바꾸면 Ansible 롤도 확인한다.
- 설치·복구 변경은 재실행 멱등성, OS·셸 차이와 실패 후 복구 경로를 고려한다.
- 변경 파일은 `bash bin/hooks/pre-flight-check.sh --changed`, 관련 회귀는 `just check-changed`로 검사한다. 범위가 넓으면 `just verify` 또는 해당 `contexts/*/tests/run.sh`도 실행한다.
- 프롬프트 수정은 `bash bin/linters/prompt-lint.sh`, context 라우팅 변경은 `just docs-index`로 확인한다.
- `WARNING`·`SKIP`·도구 미설치를 전체 검증 성공으로 해석하지 않는다. 실패·미실행을 구분하고 검증 훅을 우회하지 않는다.
- 작업에 필요할 때만 참조한다: 도구·버전은 `references/040-toolchain-management-standard.md`, 시크릿은 `references/050-dotfiles-security-standard.md`, 변경 근거 기록은 `references/010-core.md`.
- 검사 프로필·훅 동작과 도메인별 회귀 명령의 상세 기준은 `bin/README.md`와 실제 구현을 확인한다.
