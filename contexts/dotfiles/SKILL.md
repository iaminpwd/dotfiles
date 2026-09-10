---
name: dotfiles
description: |
  개인 로컬 환경 및 dotfiles 시스템 셋업 스킬. bootstrap.sh, ansible, zsh, bash, stow, mise,
  시크릿 관리, 로컬 환경 트러블슈팅.
---
# dotfiles Skill

이 스킬은 `dotfiles` 워크스페이스 환경에서 시스템 초기화 쉘 스크립트, 환경 설정 파일을 구성하고 트러블슈팅할 때 자동 발동됨.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 이 저장소 작업의 계획서·핸드오프 설계도 작성 | references/020-project-planning-template.md |
| dotfiles 아키텍처 및 핵심 구조 | references/030-dotfiles-core-standard.md |
| 도구 및 패키지 관리 (apt, mise 등) | references/040-toolchain-management-standard.md |
| 시크릿 관리, 권한 설정, 로컬 보안 정책 | references/050-dotfiles-security-standard.md |
| 환경 셋업 오류 및 런타임 트러블슈팅 | references/060-troubleshooting-standard.md |

* **공통 시스템 원칙**: references/010-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[PREFER] 필요한 참조 선택:** 라우팅 표에서 현재 작업에 해당하는 문서를 읽고, 연결된 문서는 판단에 필요한 경우에만 추가로 읽을 것. 이미 읽은 내용은 재사용할 것.
