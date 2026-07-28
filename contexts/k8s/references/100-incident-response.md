---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when investigating a K8s error, CrashLoopBackOff, pod eviction, or cluster incident.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/050-observability-standard.md
---
# 컨텍스트 모듈: K8s 장애 대응 및 사후 분석 (Incident Response)

본 모듈은 Kubernetes 클러스터 장애, Pod Eviction, CrashLoopBackOff 등 인시던트 발생 시 긴급 조치, 팩트 기반 디버깅 및 사후 RCA(근본 원인 분석) 보고서 작성 시 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Mitigation First:** 장애 접수 즉시 서비스 복구(롤백, 파드 증설, 트래픽 우회 등) 조치를 먼저 수행하십시오. 상세 원인 분석은 긴급 조치가 완료된 이후에 착수하십시오.
- **[MUST] Active Data Gathering:** 반드시 터미널에서 `kubectl get events`, `kubectl describe pod` 등의 실제 로그와 이벤트를 기계적으로 추출하여 팩트에 기반해서만 원인을 진단하십시오.
- **[MUST] Blameless RCA:** 장애 원인을 사람의 조작 실수로 규정하는 것을 배제하고, 이를 방어하지 못한 시스템적 가드레일(예: 이미지 태그 자동 검증 부재, Resource Limits 누락 등)의 공백을 규명하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 트러블슈팅 및 장애 진단
- **[PREFER] Deep Dive Analysis:** 단순 에러 문구 수집을 넘어 노드 자원 상태(`kubectl top node`), 커널 이벤트(`dmesg`), kube-apiserver 감사 로그 등을 다각도로 조회하여 장애 근본 원인을 교차 검증하십시오.
- **[MUST] Grounding 팩트 검증:** 사후 분석 보고서 작성 지시를 받으면, 실제 보고서를 출력하기 전에 반드시 `<grounding_check>` 태그를 열어 분석하려는 원인(Root Cause)과 대책(Resolution)이 수집한 터미널 출력 및 로그(팩트)와 100% 문장 단위로 일치하는지 우선 검사하십시오. 검증이 통과된 후에만 최종 보고서를 생성하십시오.

### 2.2 장애 보고서 및 포스트모템 규격
- **[Trigger: User requests bug fix or error analysis] 트러블슈팅 보고서**: 에러 분석 완료 시 아래 양식으로 `troubleshooting-report.md`를 작성하십시오.
  ```markdown
  # Troubleshooting Report
  - **Issue Summary (문제 요약)**: [발생한 문제의 증상]
  - **Root Cause (근본 원인)**: [팩트 및 이벤트 로그에 기반한 정확한 원인]
  - **Resolution (해결책)**: [적용된 매니페스트 수정 내역]
  - **Prevention (재발 방지)**: [Liveness 수정, Limit 튜닝 등 개선 계획]
  ```
- **[Trigger: Post-Incident Recovery] 포스트모템 보고서**: 운영 장애 복구 후 아래 양식으로 `post-mortem-report.md`를 작성하십시오.
  ```markdown
  # Post-Mortem Report
  - **Incident Timeline (타임라인)**: [장애 발생부터 복구까지 시간대별 기록]
  - **Impact (영향도)**: [서비스 다운타임 및 파드 Eviction 영향]
  - **Root Cause Analysis (5-Whys)**: [장애의 진짜 원인 심층 분석]
  - **Action Items (액션 아이템)**: [시스템 강건성을 위한 아키텍처 개선 후속 조치 목록]
  ```

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- CoT 기반의 구조화된 심층 분석:
  `<thinking>`
  Why 1: 파드가 왜 CrashLoopBackOff 상태인가? (OOMKilled 이벤트 반복)
  Why 2: 왜 OOM이 발생했는가? (JVM Heap Size를 컨테이너 Limit에 맞게 튜닝하지 않음)
  결론: JVM의 `-XX:MaxRAMPercentage` 옵션 누락이 근본 원인.
  `</thinking>`
  "파드의 반복적인 재시작(CrashLoopBackOff) 원인은 메모리 누수로 인한 OOMKilled입니다. JVM의 MaxRAMPercentage 옵션 누락을 해결하기 위해 매니페스트를 다음과 같이 수정하여 제안하겠습니다."
- 비난 없는 사후 분석(Blameless RCA):
  "작업자의 실수로 Pod이 삭제됨" -> "운영 환경의 배포 권한이 특정 관리자 계정으로 제한되지 않아 휴먼 에러가 시스템 장애로 이어질 수 있는 구조적 취약점이 있었음"
</example>
<example>
[Bad]
- 성급한 결론: "에러 메시지를 보니 일단 Liveness Probe 시간을 늘려보고 파드를 강제 재시작하십시오."
- 비난 조항 기재: "담당 엔지니어가 명령어를 오인하여 입력해 장애를 유발함. 담당 팀원 대상 교육을 시행하겠음." (개인을 탓함)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 수집된 K8s 이벤트가 `<grounding_check>`를 통과하여 `troubleshooting-report.md`에 결함 없이 기술되고, 재발 방지용 리소스 제한 및 가드레일 매니페스트 코드가 파일 링크 형태로 명시되어야 합니다.
- **[MUST] 검증 도구 매핑:** `kubectl get events --sort-by='.metadata.creationTimestamp'`를 사용하여 장애 시점 전후의 모든 클러스터 시스템 이벤트를 타임라인 순으로 자동 추출하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: RCA Completed] 점검 기준 (절차는 010-k8s-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (시스템적 원인 규명): 장애의 근본적인 원인이 엔지니어 부주의가 아닌 시스템적 방어가드 공백으로 명확히 도출되었는가?
  - 기준 2 (액션 아이템 구체성): 재발 예방을 위한 액션 아이템이 즉시 실행 및 코드로 검증 가능한 형태(ResourceQuota 튜닝, Probe 수정 등)로 설계되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 문제 진단 및 데이터 수집 시, 로컬에 API 호출 도구(`kubectl`)가 없거나 클러스터 접속 정보가 만료되어 데이터 팩트 수집이 3회 연속 실패할 경우 즉시 작업을 중단(Halt & Clarify)하고 정보 갱신을 요청하십시오.
  - 임시 조치(Mitigation) 전, 원인 파악을 위해 수정을 미루고 복구 적용에 브레이크를 거는 동작이 감지될 경우 작업을 멈추고 복구 조치를 먼저 취하십시오.
