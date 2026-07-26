---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing Swift object storage — storage policies, rings, replica/erasure coding, or S3-compatible access.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/030-finops-optimization.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: Swift 객체 스토리지 표준

본 모듈은 OpenStack Swift(또는 Ceph RadosGW) 기반 객체 스토리지의 내구성 정책, 컨테이너 설계 및 접근 통제 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Durability Policy:** 접근 빈도와 내구성 요구에 맞춰 Storage Policy를 분리하고, 핫 데이터는 replica 3, 콜드/대용량 데이터는 Erasure Coding으로 용량 효율을 확보하십시오.
- **[MUST] Failure Domain Ring:** 존(zone)/노드/랙 등 장애 도메인을 분리하여 ring을 구성하고, 파티션 균형을 유지하여 단일 도메인 장애가 데이터 가용성을 깨지 않게 설계하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)
- **[PREFER] Container Sharding:** 단일 컨테이너에 수백만 객체를 몰아넣지 말고 접두사 분산 또는 container sharding을 적용하여 리스팅 성능 저하를 방지하십시오.
- **[MUST] Large Object:** 5GiB를 초과하는 객체는 SLO(Static Large Object) 또는 DLO로 분할 업로드하십시오.
- **[MUST] Lifecycle & Expiry:** 임시/로그성 데이터는 `X-Delete-At`/`X-Delete-After` 헤더로 자동 만료를 설정하여 용량 누수를 차단하십시오.
- **[MUST] Encryption & Scoped Access:** 저장 암호화(Swift encryption 미들웨어 또는 백엔드 암호화)를 적용하고, 외부 공유가 필요하면 컨테이너 전체 public-read 대신 tempURL/formpost로 시간 제한 접근을 부여하십시오.
- **[MUST] Quota:** account/container 쿼터를 설정하여 특정 테넌트의 무제한 용량 증가를 사전 차단하십시오.
- **[PREFER] S3 Compatibility:** 애플리케이션이 S3 호환(S3-compatible) API를 요구하면 Swift S3 API 또는 Ceph RadosGW로 제공하되, EC2 credential과 버킷 정책 범위를 최소 권한으로 한정하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "아카이브 버킷은 Erasure Coding storage policy로 지정하고 90일 후 만료(`X-Delete-After`)를 설정하십시오."
- "외부 다운로드 링크는 tempURL로 10분 만료 서명 URL을 발급하십시오."
</example>
<example>
[Bad]
- "모든 데이터를 replica 3 단일 policy에 넣고 만료 없이 무기한 보관합니다." (용량 낭비)
- "공유가 필요하니 컨테이너를 public-read로 전체 공개합니다." (무제한 노출)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** storage policy(replica/EC), 만료 정책, 저장 암호화, account/container 쿼터가 누락 없이 선언되어야 합니다.
- **[MUST] 검증 도구 매핑:** `openstack container list`, `swift stat <container>`(policy/객체 수), `openstack object store account show`(쿼터/사용량)로 실제 구성을 기계적으로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Container Designed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (성능): 대량 객체 컨테이너에 샤딩/접두사 분산이 적용되어 리스팅 병목이 없는가?
  - 기준 2 (노출 통제): public-read 전체 공개 없이 tempURL 등 시간 제한 접근으로 격리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 민감 데이터 컨테이너가 무제한 public-read로 노출되도록 설계된 구성이 감지되면 즉시 작업을 중단(Hard Block)하고 보안 경고를 발송하십시오.
  - 저장 암호화 없이 평문으로 민감 객체가 저장되도록 설계된 경우 작업을 즉시 멈추고 암호화 적용을 강제하십시오.
