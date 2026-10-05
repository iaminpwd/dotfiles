---
name: dotfiles
description: |
  개인 로컬 환경 및 dotfiles 시스템 셋업 스킬. bootstrap.sh, ansible, zsh, bash, stow, mise,
  시크릿 관리, 로컬 환경 트러블슈팅.
---
# dotfiles Skill

이 저장소의 로컬 지침이다. 글로벌 스킬로 등록하지 않으며 루트 AGENTS.md·CLAUDE.md가 이 파일에 연결된다.

## 저장소와 검증

- 설정 원본: `stow/`, 초기 설치: `bootstrap.sh`·`ansible/`, 실행 도구: `bin/`, 지침·검증 원본: `contexts/`.
- 변경 검사: `bash bin/hooks/pre-flight-check.sh --changed`. quick은 셸·YAML·Dockerfile 린트와 Terraform 포맷, full은 인프라·보안 검사까지 포함한다.
- 변경 영역 회귀: `just check-changed`, 전체 회귀: `just test`, 전체 검증: `just verify`.
- 프롬프트 변경: `bash bin/linters/prompt-lint.sh`. 라우팅 표 변경: `just docs-index`.
- tests·evals는 런타임 스킬에 배포되지 않는다. 원본 저장소의 `contexts/<skill>/tests/`에서 실행하고 종료 코드·마지막 요약·스킵 경고를 확인한다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 이 저장소 작업의 계획서·핸드오프 설계도 작성 | references/020-project-planning-template.md |
| dotfiles 아키텍처 및 핵심 구조 | references/030-dotfiles-core-standard.md |
| 도구 및 패키지 관리 (apt, mise 등) | references/040-toolchain-management-standard.md |
| 시크릿 관리, 권한 설정, 로컬 보안 정책 | references/050-dotfiles-security-standard.md |
| 환경 셋업 오류 및 런타임 트러블슈팅 | references/060-troubleshooting-standard.md |

* 변경 범위·룰 근거 기록이 필요한 경우: references/010-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[PREFER] 필요한 참조 선택:** 라우팅 표에서 현재 작업에 해당하는 문서를 읽고, 연결된 문서는 판단에 필요한 경우에만 추가로 읽을 것. 이미 읽은 내용은 재사용할 것.
