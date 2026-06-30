---
name: dotfiles Operations
description: |
  개인 로컬 환경 및 시스템 셋업 스크립트(dotfiles) 작업 스킬입니다. 다음 작업 유형에 따라 반드시 해당 references/ 하위 문서를 먼저 읽고 지침을 따르십시오:
  - dotfiles 아키텍처 및 핵심 구조 가이드 -> references/010-dotfiles-core-standard.md
  - 쉘 스크립팅(bash/zsh) 및 setup.sh 자동화 -> references/020-shell-scripting-standard.md
  - Homebrew, apt 등 도구 및 패키지 관리 체계 -> references/030-toolchain-management-standard.md
  - 시크릿 관리, 권한 설정 등 로컬 보안 정책 -> references/040-dotfiles-security-standard.md
  - AI 에이전트 커스텀 룰, 프롬프트 엔지니어링 -> references/050-prompt-engineering-standard.md
  - 환경 셋업 오류 및 런타임 에러 트러블슈팅 -> references/060-troubleshooting-standard.md
  그 외 공통 시스템 원칙은 references/000-core.md 를 참조.
---
# dotfiles Skill

이 스킬은 `dotfiles` 워크스페이스 환경에서 시스템 초기화 쉘 스크립트, 환경 설정 파일, 그리고 로컬 AI 에이전트 아키텍처(AGENTS.md, SKILL.md 등)를 구성하고 수정할 때 자동 발동됩니다.

상세한 룰과 가이드라인은 `references/` 디렉토리 내부의 문서들을 참조하십시오.

---

> **[EXCEPTION APPLIED: Full Rule Override]**
> 본 워크스페이스는 개인의 로컬 환경 셋업과 스크립트를 관리하는 `dotfiles` 레포지토리입니다.
> 글로벌 코어 룰(`000-universal-core.md`)에 명시된 `[CORE EXCEPTION HOOK]`에 따라, 본 스킬이 발동할 때는 글로벌 코어 룰의 모든 제약 사항을 전면 무효화하고 오직 다음 예외 규칙들만을 최우선으로 적용하십시오:
> 
> 1. **빠른 실행 우선 (Speed Over Caution):** 무거운 테스트 코드 작성이나 과도하게 보수적인 오류 방어 코드를 생략하고, 즉시 실행 가능한 빠르고 직관적인 셸 스크립트 작성을 우선합니다.
> 2. **유연한 변경 (Flexible Modifications):** 전수 조사나 3단계 검증 루프를 엄격하게 거치지 않더라도, 사용자의 빠른 시스템 튜닝 목적에 맞춰 즉각적이고 가벼운 코드 수정을 허용합니다.
> 3. **간결성 극대화:** 쉘 셋업 스크립트의 특성을 고려하여, 로직을 복잡하게 설계하기보다는 단일 명령어나 직관적인 스크립트 흐름을 최우선으로 선호합니다.
