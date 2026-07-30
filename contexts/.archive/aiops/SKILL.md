---
name: aiops
description: |
  AIOps 자동화 파이프라인 스킬. SecOps, Policy-as-Code, DORA 메트릭, 카오스 엔지니어링,
  GitOps, 장애 대응 에이전트 RAG, Self-healing, RCA, 인시던트 대응,
  포스트모템(post-mortem) 리포트 작성,
  AI/ML 파이프라인 비용 최적화(GPU Spot, LLM 토큰 폭주 탐지).
---
# aiops Skill

aiops 관련 작업 시 발동됩니다. SRE 원칙 및 에이전트 기반 자동화 파이프라인 구축 시 사용하십시오.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| AIOps 프로젝트 및 자동화 파이프라인 기획 | references/020-project-planning-template.md |
| 보안(SecOps), 규정 준수(Policy-as-Code) | references/020-security-compliance.md |
| 비용 분석(FinOps), DORA 메트릭 | references/030-finops-optimization.md |
| 엣지 케이스, 복원력, 카오스 엔지니어링 | references/040-automation-scripting.md |
| IaC 및 GitOps 파이프라인 아키텍처 | references/050-iac-standard.md |
| AI 에이전트 RAG, Self-healing 워크플로우 | references/060-agent-logic.md |
| 장애 분석(RCA), 트러블슈팅, Blameless 사후 분석 | references/100-incident-response.md |

* **기본 AIOps 코어 원칙**: references/010-aiops-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 연쇄 분석 (Recursive Reference Check)**: 라우팅 테이블의 대상 룰북과 연관 참조 문서를 중복 없이 수집하여 읽으십시오. (이유: 컨텍스트 누락 방지)
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성 직후 `pre-flight-check.sh` 정량 검증을 통과시키십시오. (이유: 멱등성 및 린트 검증)
