---
role: Senior Container Platform Engineer
priority: high
trigger: Apply these rules ONLY when investigating a container runtime failure (OOMKilled, CrashLoopBackOff, ImagePullBackOff).
references:
  - contexts/containers/references/010-containers-core.md
---
# 컨테이너 런타임 장애 대응 (Incident Response)

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Mitigation First:** 장애 인지 즉시 이전 정상 이미지로 롤백하거나 리소스를 증설하는 등 서비스 정상화를 최우선으로 조치할 것. 근본 원인 분석은 복구 이후에 수행할 것.
- **[MUST] Active Data Gathering:** 반드시 `docker inspect`, `docker logs`, 또는 클러스터 이벤트(`kubectl describe pod`)로 실제 종료 코드(Exit Code)와 이벤트를 조회하여 팩트 기반으로 원인을 파악할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 종료 코드 및 실패 유형 진단
- **[PREFER] Image Pull Failure Triage:** `ImagePullBackOff`/`ErrImagePull` 발생 시 태그 오탈자, 레지스트리 인증 만료(`imagePullSecrets`), 또는 존재하지 않는 다이제스트 여부를 순서대로 확인할 것.
- **[PREFER] Layer-Level Root Cause:** 이미지 자체의 문제(엔트리포인트 오류, 누락된 런타임 의존성)가 의심될 경우 `dive <image>`로 레이어 구성과 파일 존재 여부를 검증할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- CoT 기반 원인 분석: "Exit Code 137이 확인되었으므로 OOMKilled 가능성을 우선 조사함. `docker inspect`로 `OOMKilled: true`를 확인했고, `resources.limits.memory`가 실제 힙 사용량보다 낮게 설정되어 있었습니다."
</example>
<example>
[Bad]
- 성급한 결론: "일단 컨테이너를 재시작하고 지켜보겠습니다." (팩트 조회 없이 임시방편만 반복)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 종료 코드와 이벤트 로그 기반으로 원인이 특정되고, 재발 통제를 위한 리소스 조정 또는 이미지 수정 내역이 `troubleshooting-report.md`에 정리되어야 합니다.
- **[MUST] 검증 도구 매핑:** `docker inspect`, `docker logs`, `dive`를 사용하여 종료 상태와 이미지 레이어를 기계적으로 추출할 것.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Root Cause Identified] 점검 기준 (절차는 010-containers-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (팩트 근거): 원인이 추측이 아닌 종료 코드/이벤트 로그로 명확히 뒷받침되는가?
  - 기준 2 (재발 통제): 동일 장애를 막을 구체적인 리소스/이미지 수정안이 제시되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 종료 코드나 이벤트 로그 조회 없이 원인을 추측하여 보고서를 작성하려는 시도가 감지되면 즉시 작업을 중단하고 팩트 수집을 선행할 것.
  - 임시 조치(롤백/재시작) 전에 근본 원인 분석에 시간을 소모하려는 동작이 감지되면 작업을 멈추고 복구 조치를 먼저 취할 것.
