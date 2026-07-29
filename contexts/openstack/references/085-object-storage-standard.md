---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing Swift object storage — storage policies, rings, replica/erasure coding, or S3-compatible access.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Swift 객체 스토리지 표준

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Durability Policy:** 접근 빈도와 내구성 요구에 맞춰 Storage Policy를 분리하고, 핫 데이터는 replica 3, 콜드/대용량 데이터는 Erasure Coding으로 용량 효율을 확보할 것.
- **[MUST] Failure Domain Ring:** 존(zone)/노드/랙 등 장애 도메인을 분리하여 ring을 구성하고, 파티션 균형을 유지하여 단일 도메인 장애가 데이터 가용성을 깨지 않게 설계할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)
- **[PREFER] Container Sharding:** 단일 컨테이너에 수백만 객체를 몰아넣는 대신 접두사 분산 또는 container sharding을 적용하여 효율적인 리스팅 성능을 유지할 것.
- **[MUST] Large Object:** 5GiB를 초과하는 객체는 SLO(Static Large Object) 또는 DLO로 분할 업로드할 것.
- **[MUST] Lifecycle & Expiry:** 임시/로그성 데이터는 `X-Delete-At`/`X-Delete-After` 헤더로 자동 만료를 설정하여 용량 누수를 안전하게 격리할 것.
- **[MUST] Encryption & Scoped Access:** 저장 암호화(Swift encryption 미들웨어 또는 백엔드 암호화)를 적용하고, 외부 공유가 필요하면 컨테이너 전체 public-read 대신 tempURL/formpost로 일시적 자격 증명을 부여할 것.
- **[MUST] Quota:** account/container 쿼터를 설정하여 특정 테넌트의 특정 테넌트의 상한 용량을 명시적으로 설정할 것.
- **[PREFER] S3 Compatibility:** 애플리케이션이 S3 호환(S3-compatible) API를 요구하면 Swift S3 API 또는 Ceph RadosGW로 제공하되, EC2 credential과 버킷 정책 범위를 최소 권한으로 한정할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "아카이브 버킷은 Erasure Coding storage policy로 지정하고 90일 후 만료(`X-Delete-After`)를 설정할 것."
- "외부 다운로드 링크는 tempURL로 10분 만료 서명 URL을 발급할 것."
</example>
<example>
[Bad]
- "모든 데이터를 replica 3 단일 policy에 넣고 만료 없이 무기한 보관함." (용량 낭비)
- "공유가 필요하니 컨테이너를 public-read로 전체 공개함." (상한 없는 노출)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** storage policy(replica/EC), 만료 정책, 저장 암호화, account/container 쿼터가 누락 없이 선언되어야 합니다.
- **[MUST] 검증 도구 매핑:** 지정된 린터 도구 또는 `pre-flight-check.sh`로 일괄 검증할 것. (이유: 구문 검증 강제)

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Container Designed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (성능): 대량 객체 컨테이너에 샤딩/접두사 분산이 적용되어 리스팅 병목이 없는가?
  - 기준 2 (노출 통제): tempURL 등 일시적 자격 증명을 사용하여 접근 범위가 격리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 민감 데이터 컨테이너가 무제한 public-read로 노출되도록 설계된 구성이 감지되면 즉시 작업을 중단(Hard Block)하고 보안 경고를 발송할 것.
  - 저장 암호화 없이 평문으로 민감 객체가 저장되도록 설계된 경우 작업을 즉시 멈추고 암호화 적용을 강제할 것.
