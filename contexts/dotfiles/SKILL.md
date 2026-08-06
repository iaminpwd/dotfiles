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

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 인프라 스크립트나 설정 파일을 작성하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집할 것.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `run-suite.sh` (또는 `just check`) 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `pre-flight-check` 스킬(SKILL.md)을 호출하여 동일 절차를 수행할 것.

---

> **[ EXCEPTION APPLIED: Caution Over Speed, Exhaustive Review ]**
> 완화 근거: 본 스킬이 활성화된 `dotfiles` 레포지토리는 `bin/hooks/pre-flight-check.sh`·`run-suite.sh`·시맨틱 커밋 훅 등 자동화된 안전망이 전역 룰의 수동 신중함을 상당 부분 대체하므로, 아래 2개 항목만 명시적으로 완화합니다.
> - **Caution Over Speed** (`base.AGENTS.md` 최상단): `base.AGENTS.md` §6 자체가 이미 Self-Healing·Break-Glass·Fast Fail & Halt 등 안전장치를 전역 정의하고, `bin/hooks/pre-flight-check.sh`·`run-suite.sh` 등 자동화된 안전망이 추가로 있으므로 생략.
> - **Exhaustive Review** (`base.AGENTS.md` §5.2): `references/010-core.md` §1에서 MUST를 PREFER로 낮추되, 단순 수정 작업 예외 조건은 그대로 유지.
>
> Provenance Logging(`base.AGENTS.md` §9)은 예외 대상에서 제외한다(2026-08-04 재검토: Recursive
> Reference Check는 "룰을 읽었는가", Pre-Flight Check는 "코드가 맞는가"를 확인할 뿐 "이 변경이 왜
> 이 룰 때문이었는지"를 기록하지 않아, 애초에 record-provenance.sh와 같은 역할을 대체하지 못했다 — 근거
> 없는 완화였다). 이 워크스페이스에서도 룰 근거가 있는 변경에는 `record-provenance.sh`를 정상 실행한다.
>
> 위 2개 항목을 제외한 전역 룰(보안, Git 규율, 외과적 수정, 시크릿 관리, Provenance Logging 포함)은
> 예외 없이 그대로 적용되며, `references/` 폴더 문서가 해당 항목들을 구체화합니다.
