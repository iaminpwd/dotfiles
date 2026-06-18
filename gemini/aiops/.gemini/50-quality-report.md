<aiops_quality_report>
# DevSecOps 통합 및 Policy-as-Code 컴플라이언스

## 1. 보안 규정 준수 (Shift-Left Security)
- **[MUST] Policy-as-Code:** 에이전트가 자동 생성하는 코드나 인프라 설정은 배포 전 반드시 OPA(Open Policy Agent) 또는 HashiCorp Sentinel을 이용한 정책 검증 파이프라인을 통과해야 합니다.
- **[MUST] Compliance Frameworks:** SOC2, ISO27001 등 엔터프라이즈 컴플라이언스를 위반하는 설정(예: S3 버킷 퍼블릭 오픈, 암호화 미적용 EBS)이 감지될 경우, 시스템은 절대 승인(Approve)하지 않고 명확한 컴플라이언스 위반 사유와 함께 Hard Block 처리해야 합니다.
- **[MUST] Data Privacy Guardrails:** 외부 LLM 호출 시 로그 파싱 페이로드에 포함된 고객의 민감 정보(PII, PHI, 패스워드 등)를 마스킹(Masking) 및 레드액트(Redact)하는 필터링 로직을 컴플라이언스 레벨에서 강제하십시오.
- **[MUST] Secrets Management:** 환경 변수나 에이전트 로직 내에 API Key, Token 등을 하드코딩하는 것을 엄격히 금지합니다. 모든 시크릿은 AWS Secrets Manager 또는 HashiCorp Vault를 통해 동적으로 주입(Inject) 받도록 보안 아키텍처를 강제하십시오.

## 2. 사후 분석 (Post-Mortem) 자동화
- **[MUST] Automated Timeline Extraction:** 장애(Incident) 종료 시, AI는 CloudWatch Logs, Slack 커뮤니케이션 히스토리, 변경 관리(Git Commit) 로그를 종합 분석하여 시간대별 사건 전개(Timeline)를 자동 추출해야 합니다.
- **[MUST] Blameless RCA Generation:** 추출된 타임라인을 바탕으로, `<thinking>` 태그 안에서 시스템적 약점을 추론(Systemic Remediation)한 후, 비난 없는 근본 원인 분석 보고서(Blameless RCA Report)를 반드시 `post-mortem-report.md` 전용 산출물 파일로 자동 생성하는 엔드투엔드 파이프라인을 설계하십시오.
</aiops_quality_report>
