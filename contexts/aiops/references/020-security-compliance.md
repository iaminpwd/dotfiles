---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when dealing with DevSecOps, compliance frameworks, or security policy validations.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/050-iac-standard.md
---
# 컨텍스트 모듈: DevSecOps 통합 및 컴플라이언스

본 모듈은 DevSecOps 자동화 파이프라인 설계, Policy-as-Code(PaC) 검증 및 민감 개인 정보(PII) 보호 규칙 수립 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Policy-as-Code:** 배포 승인 전에 OPA(Open Policy Agent) 또는 Sentinel을 활용한 보안 정책 검증 파이프라인(Policy-as-Code)을 통과하도록 설계하십시오.
- **[MUST] Compliance Framework Enforcement:** SOC2, ISO27001 등 컴플라이언스를 준수하도록 퍼블릭 오픈 차단 및 스토리지 암호화 적용을 강제하십시오.
- **[MUST] Centralized Secrets Management:** 코드 및 런북 내 시크릿 하드코딩을 배제하고, 모든 인증 키는 클라우드 시크릿 관리 서비스(AWS Secrets Manager, Azure Key Vault 등) 또는 HashiCorp Vault를 통해 런타임에 동적 주입받도록 강제하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 민감 정보 보호 및 시크릿 통제
- **[MUST] PII Data Privacy Guardrails:** 외부 LLM 엔드포인트 호출 및 로그 수집 시, 개인 정보(PII, 패스워드 등) 노출 방지를 위해 Presidio 등을 통한 정규식 기반 마스킹 필터링을 필수 결합하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 런타임 시크릿 로드:
```bash
export DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id prod/db --query SecretString --output text)
```
</example>
<example>
[Bad]
- 하드코딩 자격 증명 (보안 취약점 유출 안티패턴):
```bash
export DB_PASSWORD="SuperSecretPassword123!"
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 인프라 코드가 `checkov` 또는 `tfsec` 보안 스캐닝을 경고 없이 통과하고, 규정 위반 항목이 없음이 입증되어야 합니다.
- **[MUST] 검증 도구 매핑:** 코드 검증은 `contexts/pre-flight-check/SKILL.md`가 지정한 단일 래퍼 명령으로 일괄 수행하십시오. 단, `checkov` 스캔 결과 수정이 불가능한 항목은 반드시 `#checkov:skip` 주석과 근거를 명시하여 예외 처리하십시오.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Finalizing Plan] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (시크릿 격리): 파이프라인 설정 파일 및 런북 스크립트 내에 평문 자격 증명이 유출될 우려가 완벽히 배제되었는가?
  - 기준 2 (컴플라이언스 준수): SOC2/ISO27001 규정을 위반하는 퍼블릭 개방 설정이 탐지 게이트에서 차단되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - SOC2/ISO27001 규정을 정면 위반하는 인프라 설정(암호화되지 않은 볼륨, S3 버킷 `0.0.0.0/0` 퍼블릭 노출 등)이 감지되면 즉시 작업을 중단(Hard Block)하고 보안 설정을 보완하십시오.
  - 런북이나 코드 내에 API Key, 클라우드 Access Key(AWS/Azure/GCP)가 평문으로 하드코딩 유출된 패턴이 스캐닝을 통해 확인되면 즉시 작업을 멈추고 중앙 시크릿 로드 구조로 전환하십시오.
