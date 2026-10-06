---
name: dotfiles
description: |
  이 저장소의 bootstrap, Ansible, Stow, mise, shell 설정, hooks와 회귀 검증을 변경할 때 사용하는 로컬 스킬.
---
# dotfiles Skill

이 저장소의 로컬 지침이다. 글로벌 스킬로 등록하지 않으며 루트 AGENTS.md·CLAUDE.md가 이 파일에 연결된다.

## 저장소 구조와 실행 경로

- 설정 원본은 `stow/`, 초기 설치는 `bootstrap.sh`와 `ansible/`, 실행·훅 도구는 `bin/`, 지침·회귀 자산 원본은 `contexts/`다.
- 도구 버전과 mise 선언은 `stow/mise/.config/mise/config.toml`이 원본이다. 상세 계약은 `references/040-toolchain-management-standard.md`를 따른다.
- 자격 증명·SSH 키·로컬 시크릿은 저장소 밖에 두며, 상세 경계와 스캔 기준은 `references/050-dotfiles-security-standard.md`를 따른다.
- 변경 근거 기록이나 승인된 예외를 다룰 때만 `references/010-core.md`를 읽는다.

## 변경 계약

- 링크로 노출된 파일은 실제 원본을 확인한 뒤 수정한다. 사용자 파일을 일괄 덮어쓰거나 기존 링크 대상을 무조건 삭제하지 않는다.
- 배포 경로·등록·복사본을 바꾸는 작업은 `ansible/roles/ai_agent/tasks/main.yml` 등 실제 배포 코드를 확인하고, 단순 원본 내용 변경과 구분한다.
- 새 context reference를 추가·삭제·이름 변경하면 SKILL 라우팅/인용 호출부를 함께 갱신하고 `just docs-index`로 색인을 재생성한다.
- 셋업·파일 조작 변경은 fresh install과 재실행 멱등성을 고려한다. 기존 Alias·PATH·함수, OS·권한·선행 도구 조건과 충돌하지 않아야 한다.
- PATH/셸 오류는 현재 PATH, `command -v`, 실제 로드 순서를 먼저 확인한다. 원인 확인 없이 경로를 중복 추가하지 않는다.
- Stow 충돌은 기존 파일을 보존 가능한 백업 경로로 옮긴 뒤 링크를 재시도하고, 연결 후 symlink가 끊어지지 않았는지 확인한다.
- 디버그 추적(`bash -x`, `zsh -x`)은 로컬 시크릿을 출력할 수 있으므로 필요한 범위에만 사용한다.
- 복구는 이번 변경에 한정하고 사용자 변경을 보존한다. 배포 경로를 바꾼 경우에는 원본 롤백뿐 아니라 연결 복구 방법도 확인한다.

## 검증 계약

- 변경 파일 선별 검사: `bash bin/hooks/pre-flight-check.sh --changed`
- 변경 영역 회귀: `just check-changed`
- 전체 회귀: `just test`
- 전체 검증: `just verify`
- 프롬프트 변경: `bash bin/linters/prompt-lint.sh`
- context 라우팅 변경: `just docs-index`
- dotfiles 회귀 묶음은 `bash contexts/dotfiles/tests/run.sh`로 실행한다.
- tests·evals는 런타임 스킬에 배포되지 않는다. 원본 저장소에서 실행하고 종료 코드와 WARNING/SKIP을 확인한다.
