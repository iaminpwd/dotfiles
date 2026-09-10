---
name: aiops
description: |
  AIOps 자동화 파이프라인 및 SRE 스킬. 동적 임계치 시계열 이상 탐지, 탐지→진단→대응→검증 Closed-Loop 자동화,
  이종 텔레메트리(메트릭·로그·트레이스) 수집, RAG 인시던트 지식베이스, Self-Healing, 서비스 토폴로지 RCA,
  금융권 보안(ISMS-P, 데이터 비식별화, 망분리 프라이빗 LLM 게이트웨이), MTTD/MTTR 측정 및 AIOps 성숙도 로드맵,
  SecOps, Policy-as-Code, DORA 메트릭, 카오스 엔지니어링, GitOps, 포스트모템(post-mortem) 리포트 작성.
---
# aiops Skill

aiops 관련 작업 시 발동됩니다. SRE 원칙 및 에이전트 기반 자동화 파이프라인 구축 시 사용하십시오.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| AIOps 프로젝트 및 자동화 파이프라인 기획 | references/005-project-planning-template.md |
| 보안(SecOps), 규정 준수(ISMS-P/비식별화) | references/020-security-compliance.md |
| 비용 분석(FinOps), DORA 메트릭 | references/030-finops-optimization.md |
| 엣지 케이스, 복원력, 카오스 엔지니어링 | references/040-resiliency-chaos-standard.md |
| IaC 및 GitOps 파이프라인 아키텍처 | references/050-iac-standard.md |
| AI 에이전트 RAG, Self-healing 워크플로우 | references/060-agent-logic.md |
| 장애 분석(RCA), 트러블슈팅, Blameless 사후 분석 | references/100-incident-response.md |
| Closed-Loop 명세 및 RAG 참조 파이프라인 코드 예시 | examples/ |
| 텔레메트리 파이프라인 및 동적 임계치 정량 검증 도구 | scripts/ |
| scripts/examples 회귀 테스트 실행 | tests/run.sh |

* **기본 AIOps 코어 원칙**: references/010-aiops-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[PREFER] 필요한 참조 선택:** 라우팅 표에서 현재 작업에 해당하는 문서를 읽고, 연결된 문서는 판단에 필요한 경우에만 추가로 읽을 것. 이미 읽은 내용은 재사용할 것.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 변경 완료 시 관련 파일의 `pre-flight-check.sh` 정량 검증 결과를 확인할 것. 실행 시점과 결과 보고는 `contexts/pre-flight-check/SKILL.md`를 따른다.
