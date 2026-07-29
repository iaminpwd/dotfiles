---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when working with Kubernetes on OpenStack via Magnum, Cluster API, Helm, or container orchestration.
references:
  - contexts/openstack/references/050-iac-standard.md
  - contexts/openstack/references/020-security-compliance.md
  - contexts/openstack/references/025-cloud-security.md
  - contexts/openstack/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Kubernetes on OpenStack (Magnum) 특화 표준

본 모듈은 OpenStack Magnum 기반 Kubernetes 클러스터 설계, 컨테이너 오케스트레이션 및 Helm 패키지 배포 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege (cloud-provider-openstack):** 워크로드(Pod)가 OpenStack 리소스(Cinder 볼륨, Octavia LB)에 접근할 때, 노드 전역 자격 대신 Application Credential 기반 `cloud.conf`를 Secret으로 주입하여 클러스터 단위 최소 권한을 달성하십시오.
- **[MUST] Secret Encryption (Prod):** 프로덕션 클러스터의 K8s Secret에는 반드시 EncryptionConfiguration(KMS/aescbc)을 적용하고, 키는 Barbican/Castellan과 연동하십시오. 개발/테스트 클러스터에는 권장하되 프로덕션 매니페스트와는 별도 파일로 분리 관리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Magnum 클러스터 및 노드 구성
- **[MUST] Cluster Template as Code:** 클러스터는 `openstack coe cluster template create` 파라미터를 IaC로 관리하고, COE는 `kubernetes`로 고정, `docker_volume_size`·`master_flavor`·`flavor`를 워크로드에 맞춰 명시하십시오.
- **[PREFER] Node Group 분리:** master/worker 및 워크로드 등급별로 Node Group을 분리하고, 오토스케일링이 필요하면 `--min-nodes`/`--max-nodes`로 cluster-autoscaler를 활성화하십시오.
- **[PREFER] Cluster API 대안:** Magnum 미제공/버전 제약 환경에서는 Cluster API Provider OpenStack(CAPO)를 대안으로 제안하여 선언적 클러스터 수명 주기를 관리하십시오.
- **[MUST] LB & Storage Integration:** Service `type=LoadBalancer`는 Octavia로, PVC는 Cinder CSI(`cinder.csi.openstack.org`)로 프로비저닝되도록 스토리지 클래스를 구성하십시오.

### 2.2 공통 K8s 코어 룰 참조
- **[MUST] Reference Generic K8s Rules:** 쿠버네티스 공통 기능(네트워크, 스토리지, 파드 생명주기, GitOps 등) 작업 시, 반드시 홈 디렉토리($HOME) 내에 기 설정된 `~/dotfiles/contexts/k8s/SKILL.md` 파일을 절대 경로로 조립하여 먼저 읽고(View), 그 안에 명시된 라우팅 가이드에 따라 `references/` 하위의 적절한 코어 룰을 참조하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- cloud.conf 최소 권한 주입: Application Credential로 발급한 자격을 K8s Secret으로 마운트하여 cloud-provider-openstack에 전달하십시오.
</example>
<example>
[Bad]
- 노드 전역 자격 남용: "Pod가 볼륨을 붙여야 하므로 worker 노드의 admin 자격을 그대로 클러스터 전체에 공유하겠습니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 생성될 K8s 매니페스트/Helm 차트 린트가 경고 없이 패스되고, API 리소스 스키마가 대상 클러스터 K8s 버전에 유효함이 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** 클러스터 생성 전 `openstack coe cluster template list`로 규격을 대조하며 참조하는 리소스의 실존 여부를 사전 확인하십시오. 코드 검증은 `contexts/pre-flight-check/SKILL.md`가 지정한 단일 래퍼 명령으로 일괄 수행하십시오.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Cluster Config Proposed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (워크로드 권한 격리): 노드 전역 자격 대신 Application Credential 기반 `cloud.conf`가 클러스터 단위로 매핑되었는가?
  - 기준 2 (보안 통제): 클러스터 API Endpoint가 퍼블릭 차단 또는 화이트리스트 CIDR 기반으로 격리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - Secret 암호화(EncryptionConfiguration) 연동 없이 기본 평문 base64 Secret 저장 방식으로 프로덕션 코드가 설계되었을 시 즉시 작업을 멈추고 보안 수정을 적용(Hard Block)하십시오. (`privileged`/`hostNetwork` 등 파드 보안 컨텍스트 일반 위반은 `k8s` 스킬의 중단 조건을 참조하십시오.)
