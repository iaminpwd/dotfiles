---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when planning, architecting, or creating a Master Plan for a new AIOps or Automation project.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/020-security-compliance.md
  - contexts/aiops/references/030-finops-optimization.md
---
# 컨텍스트 모듈: AIOps 파이프라인 마스터 플랜(계획서) 작성 표준

새로운 SRE 자동화 파이프라인 및 AI 에이전트 마스터 플랜 작성 시 적용되는 표준입니다.

## 1. 핵심 설계 원칙
- **[MUST] Use Built-in Artifact:** 내장 `implementation_plan.md` 아티팩트로 계획서를 작성하십시오. (이유: 시스템 내장 워크플로우 호환성)
- **[PREFER] Agentic RAG:** 설계 전 사내 표준(SSOT) 룰북을 조회하여 계획서에 반영하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 마스터 플랜 뼈대 강제 (Master Plan Schema)
계획서 작성 시 아래 목차와 요구사항을 반드시 준수하십시오.
1. **프로젝트 요약 (Executive Summary)**: 자동화 목표 및 SRE 핵심 지표(MTTR 단축, DORA 메트릭 등)를 명시하십시오.
2. **아키텍처 청사진 (Architecture Blueprint) & ADR**: 전체 시스템 구성도를 설계하고, 도입 기술에 대해 ADR(Architecture Decision Records) 형식을 적용하여 대안 평가 및 채택 사유를 명시하십시오.
3. **관측성 및 텔레메트리 (Observability & Telemetry)**: 로그 수집, 분산 트레이싱, DORA 지표 연동 계획을 수립하십시오.
4. **비용 및 리소스 최적화 (FinOps)**: 예측 비용 및 컴퓨팅 자원의 스케일링 리미트를 명시하십시오.
5. **멱등성 및 상태 관리 (Idempotency & State)**: 중복 실행을 막기 위한 멱등 키(Idempotency Key) 및 상태 잠금 로직을 설계하십시오.
6. **장애 허용 및 안전망 (Resiliency & Guardrails)**: 서킷 브레이커, DLQ 연동, Human-in-the-loop(수동 승인) 등 파괴적 명령에 대한 방어 가드레일을 명시하십시오.
7. **자동화 검증 (Eval-Driven Testing)**: 시스템 정상 작동을 확인하는 Fault Injection 및 카오스 엔지니어링 검증 방안을 포함하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 아키텍처 청사진 ADR: "기존의 Jenkins 수동 빌드 방식 대신, 리스크 격리를 위해 GitHub Actions와 ArgoCD Pull-based GitOps 방식을 채택합니다. 이를 통해 동기화 이력을 Git에 영구 기록합니다."
</example>
<example>
[Bad]
- 모호한 아키텍처 계획: "배포는 적당한 CI/CD 도구를 사용해 자동화할 계획임." (ADR 근거 및 설계 구체성 결여)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `implementation_plan.md` 규격 준수, 보안/멱등성 점검 통과, 마크다운 렌더링 정상. (이유: 기획 결함 방지)
- **[MUST] 검증 도구 매핑:** `markdownlint`로 형식 및 가독성을 자동 검증하십시오. (이유: 문서 품질 유지)

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Finalizing Plan] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (설계 강건성): 보안(Credential 관리)과 멱등성(중복 실행 방어)이 완벽하게 아키텍처 설계 상에 보장되었는가?
  - 기준 2 (리스크 완화): 자동화 오작동으로 인한 자원 파괴(Delete) 및 권한 남용을 차단하는 Guardrail이 포함되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 자동화 파이프라인 내에 수동 승인 게이트(Human-in-the-loop) 없이 프로덕션 리소스를 파괴적으로 삭제/변경하는 자동화 룰이 감지될 시 즉시 작업을 중단(Halt & Clarify)하고 가드레일을 설계하십시오.
  - 아키텍처 설계안 중 대체 기술에 대한 정량적 대안 분석 테이블(ADR)이 누락된 경우 작업을 즉시 멈추고 보완을 요구하십시오.
