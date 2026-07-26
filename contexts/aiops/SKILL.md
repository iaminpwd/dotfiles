---
name: aiops
description: |
  AIOps 자동화 파이프라인 스킬. SecOps, Policy-as-Code, FinOps, DORA 메트릭,
  카오스 엔지니어링, IaC, GitOps, AI 에이전트 RAG, Self-healing, RCA, 인시던트 대응.
reviewed: 2026-07-21
---
# aiops Skill

이 스킬은 aiops 관련 작업 시 발동됩니다.
SRE의 신뢰성 중심 원칙과 LLM 에이전트 기반의 자동화 파이프라인을 구축할 때 사용하십시오.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| AIOps 프로젝트 및 자동화 파이프라인 기획 | references/005-project-planning-template.md |
| 보안(SecOps), 규정 준수(Policy-as-Code) | references/020-security-compliance.md |
| 비용 분석(FinOps), DORA 메트릭 | references/030-finops-optimization.md |
| 엣지 케이스, 복원력, 카오스 엔지니어링 | references/040-automation-scripting.md |
| IaC 및 GitOps 파이프라인 아키텍처 | references/050-iac-standard.md |
| AI 에이전트 RAG, Self-healing 워크플로우 | references/060-agent-logic.md |
| 장애 분석(RCA), 트러블슈팅, Blameless 사후 분석 | references/100-incident-response.md |

* **기본 AIOps 코어 원칙**: references/010-aiops-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: AIOps 및 자동화 파이프라인 코드를 작성하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `pre-flight-check.sh` 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `~/dotfiles/contexts/pre-flight-check/SKILL.md`를 절대 경로로 읽어 동일 절차를 수행하십시오.
