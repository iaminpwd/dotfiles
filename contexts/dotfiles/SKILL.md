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

# Dotfiles Management Skill

> **[ EXCEPTION APPLIED: FULL RULE OVERRIDE ]**
> 주의: 본 스킬이 활성화된 `dotfiles` 레포지토리에서는 전역 룰(`000-universal-core.md`)에 명시된 보수적 제약(Caution Over Speed, 전수 조사 등)을 **즉시 전면 무효화(Bypass)**합니다.
> 
> **[이 워크스페이스 전용 3대 코어 원칙]**
> 1. **Speed Over Caution:** 테스트 코드나 과도한 에러 방어 로직 생략. 즉시 실행 가능한 직관적인 쉘 스크립트 작성을 최우선시합니다.
> 2. **Surgical & Fast:** 거대한 아키텍처 단위의 3단계 검증이나 전수 조사는 생략하며, 사용자의 시스템 튜닝 목적에 맞춘 즉각적이고 가벼운 코드 수정을 허용합니다.
> 3. **Keep it Simple:** 복잡한 설계 대신 단일 명령어와 직관적인 쉘 흐름을 선호합니다.
> 
> **[ 예외: 필수 로컬 검증 (Active Investigation) ]**
> 속도를 중시하더라도, **기존 설정 파괴 및 중복 선언 방지(멱등성)**를 위해 다음의 최소한의 실태 조사와 검증은 **반드시** 거쳐야 합니다.
> 
> - **[MUST] 3D Local Verification Delegation:** 로컬 쉘 스크립트를 작성하거나 패키지를 설치할 때, 반드시 `references/010-dotfiles-core-standard.md` 문서를 열람(Read)하여 **[Active Investigation & 3D Local Verification]** 규칙을 숙지하십시오. 그 후, 해당 기준에 따라 `<thinking>` 태그 내에서 사전 검증(멱등성, 충돌, 의존성)을 수행하고 요약 보고하십시오.
