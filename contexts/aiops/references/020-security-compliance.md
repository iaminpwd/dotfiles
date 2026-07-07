---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when dealing with DevSecOps, compliance frameworks, or security policy validations.
---
# 컨텍스트 모듈: DevSecOps 통합 및 컴플라이언스

## 1. 보안 규정 준수 (Shift-Left Security & PaC)
- **[MUST] Policy-as-Code (PaC):** 에이전트가 자동 생성하는 IaC 코드나 인프라 설정은 배포 승인 전에 반드시 OPA(Open Policy Agent) 또는 HashiCorp Sentinel을 활용한 보안 정책 검증 파이프라인(Policy-as-Code)을 통과하도록 파이프라인을 설계하십시오.
- **[MUST] Compliance Framework Enforcement:** 엔터프라이즈 SOC2, ISO27001 컴플라이언스를 정면으로 위반하는 설정(예: S3 버킷 퍼블릭 오픈, 암호화 미적용 데이터베이스 볼륨)이 감지될 경우, 시스템 배포를 절대 승인(Approve)하지 않고 명확한 규정 위반 사유와 함께 Hard Block 처리해야 합니다.

## 2. 민감 정보 보호 (Data Privacy & Secrets)
- **[MUST] PII Data Privacy Guardrails:** 외부 LLM 엔드포인트 호출 시, 에러 로그 파싱 페이로드에 포함된 고객의 민감 정보(PII, PHI, 패스워드, 이메일 등)를 Presidio나 AWS Macie 수준의 로직을 통해 철저히 마스킹(Masking) 및 레드액트(Redact)하는 필터링 파이프라인을 컴플라이언스 룰로서 강제하십시오.
- **[MUST] Centralized Secrets Management:** 런북(Runbook) 스크립트, 환경 변수, 에이전트 로직 내부에 API Key나 인증 토큰을 하드코딩하는 것을 치명적 보안 위반으로 간주합니다. 모든 시크릿은 AWS Secrets Manager 또는 HashiCorp Vault와 같은 중앙화된 시크릿 저장소에서 런타임에 동적으로 주입(Inject) 받도록 보안 아키텍처를 강제하십시오.
