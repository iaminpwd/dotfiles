---
name: aiops
description: |
  AIOps 자동화 파이프라인 스킬. SecOps, Policy-as-Code, FinOps, DORA 메트릭,
  카오스 엔지니어링, IaC, GitOps, AI 에이전트 RAG, Self-healing, RCA, 인시던트 대응.
---
# aiops Skill

이 스킬은 aiops 관련 작업 시 발동됩니다.
단순 스크립팅을 넘어 SRE의 신뢰성 중심 원칙과 LLM 에이전트 기반의 자동화 파이프라인을 구축할 때 사용하십시오.

## 작업 유형별 참조 문서 라우팅

| 작업 유형 | 참조 문서 |
|-----------|----------|
| AIOps 프로젝트 및 자동화 파이프라인 기획 | references/005-project-planning-template.md |
| 보안(SecOps), 규정 준수(Policy-as-Code) | references/020-security-compliance.md |
| 비용 분석(FinOps), DORA 메트릭 | references/030-finops-optimization.md |
| 엣지 케이스, 복원력, 카오스 엔지니어링 | references/040-automation-scripting.md |
| IaC 및 GitOps 파이프라인 아키텍처 | references/050-iac-standard.md |
| AI 에이전트 RAG, Self-healing 워크플로우 | references/060-agent-logic.md |
| 장애 분석(RCA), 트러블슈팅, Blameless 사후 분석 | references/100-incident-response.md |

기본 AIOps 코어 원칙: references/010-aiops-core.md

## [MUST] 작업 시작 전 필수 사전 분석

Terraform, Ansible, 쉘 스크립트 등 자동화 및 인프라 코드를 신규 작성하거나 수정을 시작하기 전에, **어떠한 도구 실행이나 코드 작성을 수행하기 전** 반드시 아래 절차를 따르십시오.

1. 본 스킬 문서 내 "작업 유형별 참조 문서 라우팅" 테이블에서 요청받은 태스크와 일치하는 대상 참조 문서를 찾으십시오.
2. 해당 참조 문서(예: `references/050-iac-standard.md` 등)를 `view_file` 도구로 먼저 읽어 그 안에 명시된 설계 및 보안 표준을 파악한 후 코딩에 착수하십시오.

## [MUST] IaC/스크립트 코드 수정 후 필수 후속 동작

Terraform, Ansible, 쉘 스크립트 등 자동화 및 인프라 코드를 신규 작성하거나 수정한 경우, **작업 완료를 선언하기 전에** 반드시 아래 절차를 따르십시오.

1. `Pre-Flight Check` 스킬의 `SKILL.md`를 `view_file` 도구로 직접 읽으십시오.
2. 해당 SKILL.md에 명시된 `pre-flight-check.sh` 연결 및 실행 절차를 그대로 수행하십시오.

