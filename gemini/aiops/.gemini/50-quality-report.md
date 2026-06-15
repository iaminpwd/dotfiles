# DevSecOps 통합 및 Policy-as-Code 컴플라이언스

## 1. 보안 규정 준수 (Shift-Left Security)
- **[MUST] Policy-as-Code:** 에이전트가 자동 생성하는 코드나 인프라 설정은 배포 전 반드시 OPA(Open Policy Agent) 또는 HashiCorp Sentinel을 이용한 정책 검증 파이프라인을 통과해야 합니다.
- **[MUST] Compliance Frameworks:** SOC2, ISO27001 등 엔터프라이즈 컴플라이언스를 위반하는 설정(예: S3 버킷 퍼블릭 오픈, 암호화 미적용 EBS)이 감지될 경우, 시스템은 절대 승인(Approve)하지 않고 명확한 컴플라이언스 위반 사유와 함께 Hard Block 처리해야 합니다.

## 2. 사후 분석 (Post-Mortem) 자동화
- **[MUST] Automated Timeline Extraction:** 장애(Incident) 종료 시, AI는 CloudWatch Logs, Slack 커뮤니케이션 히스토리, 변경 관리(Git Commit) 로그를 종합 분석하여 시간대별 사건 전개(Timeline)를 자동 추출해야 합니다.
- **[MUST] Blameless RCA Generation:** 추출된 타임라인을 바탕으로, 사람의 실수가 아닌 시스템적 예방책(Systemic Remediation)에 초점을 맞춘 '비난 없는 근본 원인 분석 보고서(Blameless RCA Report)' 마크다운을 자동 생성하는 엔드투엔드 파이프라인을 설계하십시오.
