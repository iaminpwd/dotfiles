---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when investigating an error, bug, or system incident on OpenStack.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/020-security-compliance.md
---
# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

본 모듈은 OpenStack 서비스 장애 인시던트 발생 시의 긴급 복구, 근본 원인 분석(RCA) 및 비난 없는 사후 분석(Blameless Post-Mortem) 보고서 작성 시 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Mitigation First:** 장애 인지 즉시 서비스 정상화(복구/롤백) 조치를 최우선으로 실행하십시오. 원인 파악 및 코드 수정은 긴급 복구가 완료된 뒤 수행하십시오.
- **[MUST] Active Data Gathering:** 반드시 로컬 `openstack` CLI 조회 결과와 서비스 로그(nova/neutron/cinder), `ceph health` 등 팩트만을 근거로 원인을 파악하십시오.
- **[MUST] Blameless RCA:** 휴먼 에러를 방어하지 못한 시스템적 결함(예: `prevent_destroy` 누락, 쿼터 가드레일 부재, 광역 role assignment 등)을 역추적하여 개선책을 마련하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 트러블슈팅 및 장애 진단
- **[PREFER] Deep Dive Analysis:** 단순 표면 오류 문구 수집을 넘어, 필요시 Neutron 포트/라우터 상태, Nova 스케줄러 로그, RabbitMQ 큐 적체, Galera 동기화 상태를 다각도로 수집하여 입출력 양방향 흐름을 교차 검증하십시오.
- **[MUST] Grounding 팩트 검증:** 사후 분석 보고서 작성 지시를 받으면, 실제 보고서를 출력하기 전에 반드시 `<grounding_check>` 태그를 열어 분석하려는 원인(Root Cause)과 대책(Resolution)이 수집한 터미널 출력 및 로그(팩트)와 100% 문장 단위로 일치하는지 우선 검사하십시오. 검증 통과 후에만 최종 보고서를 생성하십시오.
- **[PREFER] Timeline Standardization:** 다중 팀 대응이 필요한 대형 장애는 CADF 감사 로그와 서비스 타임스탬프를 기준으로 타임라인을 표준화하여 대응 채널에 공유하십시오.

### 2.2 장애 보고서 및 포스트모템 규격
- **[Trigger: Error Analysis Request] 트러블슈팅 보고서**: 에러 분석 완료 시 아래 양식으로 `troubleshooting-report.md`를 작성하십시오.
  ```markdown
  # Troubleshooting Report
  - **Issue Summary (문제 요약)**: [발생한 문제의 증상]
  - **Root Cause (근본 원인)**: [팩트 및 로그에 기반한 정확한 원인]
  - **Resolution (해결책)**: [적용된 코드/인프라 수정 내역]
  - **Prevention (재발 방지)**: [동일 에러 방지용 가드레일 추가 계획]
  ```
- **[Trigger: Post-Incident Recovery] 포스트모템 보고서**: 운영 장애 복구 후 아래 양식으로 `post-mortem-report.md`를 작성하십시오.
  ```markdown
  # Post-Mortem Report
  - **Incident Timeline (타임라인)**: [장애 발생부터 복구까지 시간대별 기록]
  - **Impact (영향도)**: [서비스 다운타임 및 사용자/비즈니스 영향]
  - **Root Cause Analysis (5-Whys)**: [장애의 진짜 원인 심층 분석]
  - **Action Items (액션 아이템)**: [시스템 강건성을 위한 아키텍처 개선 후속 조치 목록]
  ```

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "작업자의 실수로 볼륨이 삭제됨" -> "프로덕션 볼륨에 prevent_destroy 락과 쿼터 가드레일이 없어 휴먼 에러가 시스템 파괴로 이어질 수 있는 구조적 취약점이 있었음"
</example>
<example>
[Bad]
- "담당자가 주의를 기울이지 않아 발생함. 앞으로 교육을 통해 주의를 주겠음." (개인을 탓함)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 수집된 에러 로그가 `<grounding_check>` 검증을 거쳐 `troubleshooting-report.md` 및 `post-mortem-report.md`에 결함 없이 정리되고, 재발 방지 액션 아이템이 파일 링크 형태로 보증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `openstack server event list`, `openstack network agent list`, 서비스 로그(`journalctl`/Kolla 컨테이너 로그) 및 `ceph -s`를 활용하여 팩트 로그 상태를 기계적으로 추출하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: RCA Completed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (시스템적 원인 규명): 장애 원인이 사람의 부주의(Human Error)가 아닌 시스템적/구조적 결함으로 상세히 귀결되었는가?
  - 기준 2 (액션 아이템의 구체성): 재발 예방 액션 아이템이 즉시 실행 가능한 형태(설정 파일 링크, 스크립트 수정 등)로 제시되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 데이터 수집 시, 로컬에 핵심 CLI 도구(`openstack`)가 누락되어 있거나 인증 권한 오류(`HTTP 401/403`)로 인해 팩트 수집이 3회 연속 실패할 경우 즉시 작업을 중단(Halt & Clarify)하고 권한을 요청하십시오.
  - 임시 조치(Mitigation) 전, 장애 원인을 캐내기 위해 수정을 뒤로 미루고 복구 적용에 브레이크를 거는 동작이 확인될 시 작업을 멈추고 복구 최우선 조치를 먼저 취하십시오.
