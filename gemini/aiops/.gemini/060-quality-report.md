<aiops_quality_report>
# 컨텍스트 모듈: DevSecOps 통합, 컴플라이언스 및 사후 분석(Post-Mortem) 자동화

## 1. 보안 규정 준수 (Shift-Left Security & PaC)
- **[MUST] Policy-as-Code (PaC):** 에이전트가 자동 생성하는 IaC 코드나 인프라 설정은 배포 승인 전에 반드시 OPA(Open Policy Agent) 또는 HashiCorp Sentinel을 활용한 보안 정책 검증 파이프라인(Policy-as-Code)을 통과하도록 파이프라인을 설계하십시오.
- **[MUST] Compliance Framework Enforcement:** 엔터프라이즈 SOC2, ISO27001 컴플라이언스를 정면으로 위반하는 설정(예: S3 버킷 퍼블릭 오픈, 암호화 미적용 데이터베이스 볼륨)이 감지될 경우, 시스템 배포를 절대 승인(Approve)하지 않고 명확한 규정 위반 사유와 함께 Hard Block 처리해야 합니다.
- **[MUST] PII Data Privacy Guardrails:** 외부 LLM 엔드포인트 호출 시, 에러 로그 파싱 페이로드에 포함된 고객의 민감 정보(PII, PHI, 패스워드, 이메일 등)를 Presidio나 AWS Macie 수준의 로직을 통해 철저히 마스킹(Masking) 및 레드액트(Redact)하는 필터링 파이프라인을 컴플라이언스 룰로서 강제하십시오.
- **[MUST] Centralized Secrets Management:** 런북(Runbook) 스크립트, 환경 변수, 에이전트 로직 내부에 API Key나 인증 토큰을 하드코딩하는 것을 치명적 보안 위반으로 간주합니다. 모든 시크릿은 AWS Secrets Manager 또는 HashiCorp Vault와 같은 중앙화된 시크릿 저장소에서 런타임에 동적으로 주입(Inject) 받도록 보안 아키텍처를 강제하십시오.

## 2. 사후 분석 (Post-Mortem) 자동화 파이프라인
- **[MUST] Automated Timeline Extraction:** 장애(Incident) 종료 시, AI 파이프라인은 단순히 "해결 완료"로 끝나지 않고 CloudWatch Logs, Slack 메신저 커뮤니케이션 히스토리, Git 변경 관리(Commit) 내역을 종합 수집 및 분석하여 시간대별 사건 전개(Timeline)를 자동 추출하는 워크플로우를 갖춰야 합니다.
- **[Trigger: Post-Incident / Resolution] Blameless RCA Generation (사후 분석 보고서 생성):**
  > 장애 파이프라인 복구가 완료되었거나 분석 요청을 처리한 직후, `<thinking>` 태그 내에서 시스템적 약점(Systemic Remediation)을 철저히 추론하십시오. 이후 개인에 대한 비난 없는 근본 원인 분석 보고서(Blameless RCA Report)를 반드시 전용 산출물인 `post-mortem-report.md` 파일로 자동 생성하십시오.
  > 보고서에는 다음 항목이 필수로 포함되어야 합니다:
  > - 현상(Symptom) 및 타임라인
  > - 근본 원인(Root Cause - 시스템 구조적 한계점)
  > - 즉각적 완화 조치(Resolution)
  > - 향후 재발 방지를 위한 자동화 및 인프라 Action Items

## 3. 에러 분석 및 디버깅 결과의 구조화
- **[Trigger: User requests bug fix or error analysis] 분석 결과 구조화 (Structured Analysis):**
  > 챗 창에서 에러 코드를 분석할 때 무분별하게 수정 코드만 출력하지 마십시오. 반드시 산출물 파일인 `troubleshooting-report.md`에 다음 순서로 결과를 문서화하십시오:
  > 1. Root Cause Analysis (근본 원인 분석)
  > 2. Logical Basis (시스템 로그 및 터미널 출력 기반 증거)
  > 3. Step-by-Step Solution & Modified Code (해결 절차)
  > 4. Prevention Plan (베스트 프랙티스 기반 재발 방지책)
</aiops_quality_report>