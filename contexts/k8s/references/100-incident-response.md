---
trigger: Apply these rules ONLY when investigating a K8s error, CrashLoopBackOff, pod eviction, or cluster incident.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/050-observability-standard.md
---
# 컨텍스트 모듈: K8s 장애 대응 및 사후 분석 (Incident Response)

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Mitigation First:** 장애 접수 즉시 서비스 복구(롤백, 파드 증설, 트래픽 우회 등) 조치를 먼저 수행할 것. 상세 원인 분석은 긴급 조치가 완료된 이후에 착수할 것.
- **[MUST] Active Data Gathering:** 반드시 터미널에서 `kubectl get events`, `kubectl describe pod` 등의 실제 로그와 이벤트를 기계적으로 추출하여 팩트에 기반해서만 원인을 진단할 것.
- **[MUST] Blameless RCA:** 장애 원인을 사람의 조작 실수로 규정하는 대신, 이를 방어하지 못한 시스템적 가드레일(예: 이미지 태그 자동 검증 부재, Resource Limits 누락 등)의 공백을 규명할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 트러블슈팅 및 장애 진단
- **[PREFER] Deep Dive Analysis:** 파드 로그 외에 노드 자원 상태(`kubectl top node`), 커널 이벤트(`dmesg`), kube-apiserver 감사 로그를 추가 조회하여 장애 근본 원인을 교차 검증할 것.
- **[MUST] Grounding 팩트 검증:** 장애 보고서에서 관측 사실, 원인 가설, 제안 대책을 구분할 것. 사실과 확정 원인에는 수집된 로그·이벤트 등 근거를 연결하고, 근거가 부족하면 미확정으로 표시하고 필요한 추가 조사를 명시할 것.

### 2.2 장애 보고서 및 포스트모템 규격
- **[Trigger: Troubleshooting Report Requested] 트러블슈팅 보고서**: 별도 보고서를 요청받으면 아래 구성을 참고하고, 지정된 경로·형식에 작성할 것. 지정이 없으면 `troubleshooting-report.md`를 사용할 수 있음.
  ```markdown
  # Troubleshooting Report
  - **Issue Summary (문제 요약)**: [발생한 문제의 증상]
  - **Root Cause (근본 원인)**: [팩트 및 이벤트 로그에 기반한 정확한 원인]
  - **Resolution (해결책)**: [적용된 매니페스트 수정 내역]
  - **Prevention (재발 통제)**: [Liveness 수정, Limit 튜닝 등 개선 계획]
  ```
- **[Trigger: Post-Mortem Requested] 포스트모템 보고서**: 장애 사후 분석 문서를 요청받으면 아래 구성을 참고하고, 지정된 경로·형식에 작성할 것. 지정이 없으면 `post-mortem-report.md`를 사용할 수 있음.
  ```markdown
  # Post-Mortem Report
  - **Incident Timeline (타임라인)**: [장애 발생부터 복구까지 시간대별 기록]
  - **Impact (영향도)**: [서비스 다운타임 및 파드 Eviction 영향]
  - **Root Cause Analysis (5-Whys)**: [장애의 진짜 원인 심층 분석]
  - **Action Items (액션 아이템)**: [시스템 강건성을 위한 아키텍처 개선 후속 조치 목록]
  ```

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 요청 범위의 조사·수정 결과, 확인된 근거와 미확정 사항, 필요한 후속 조치를 보고할 것. 코드 수정이 포함되면 해당 검증 결과를 함께 제시하고, 별도 보고서 파일은 요청된 경우에 작성할 것.
- **[MUST] 검증 도구 매핑:** `kubectl get events --sort-by='.metadata.creationTimestamp'`를 사용하여 장애 시점 전후의 모든 클러스터 시스템 이벤트를 타임라인 순으로 자동 추출할 것.

## 4. 변경 전 확인과 실행 경계
- **[MUST] 중단 조건 (Halt Conditions):**
  - 문제 진단 및 데이터 수집 시, 로컬에 API 호출 도구(`kubectl`)가 없거나 클러스터 접속 정보가 만료되어 데이터 팩트 수집이 3회 연속 실패할 경우 즉시 작업을 중단(Halt & Clarify)하고 정보 갱신을 요청할 것.
  - 임시 조치(Mitigation) 전, 원인 파악을 위해 수정을 미루고 복구 적용에 브레이크를 거는 동작이 감지될 경우 작업을 멈추고 복구 조치를 먼저 취할 것.
