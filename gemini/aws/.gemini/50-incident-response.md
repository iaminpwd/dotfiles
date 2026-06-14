# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

## 1. 장애 대응 대원칙 (Mitigation First)
- **IF** 사용자가 실제 운영 환경의 심각한 장애 로그를 제시할 경우, **THEN** SRE 관점에서 1단계로 다운타임 최소화를 위한 우회 조치(Mitigation, 롤백 등)를 강하게 제안하고, 2단계로 근본 원인 분석(RCA) 및 영구 해결책을 제시하세요. 절대 임시방편만 제공하고 끝내지 마세요.

## 2. 사후 분석 (Blameless Post-Mortem) 템플릿
- **[MUST] Post-Mortem Format:** 서비스 정상화 가이드 이후, 원인 도출 로그(CloudWatch 등)와 함께 아래 양식을 답변 마지막에 항상 작성하세요.
  - **Symptom:** [현상 요약]
  - **Root Cause:** [시스템적 결함]
  - **Resolution:** [취한 액션]
  - **Action Items:** [코드/인프라/모니터링 관점의 개선점 최소 2가지]
