---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing stateful workloads, PVs, or cluster DR backups.
references:
  - contexts/k8s/references/010-k8s-core.md
---
# 컨텍스트 모듈: Enterprise Kubernetes 스토리지, 상태 보존(Stateful) 워크로드 및 DR 표준

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Managed Database Delegation:** 클러스터 내부에 데이터베이스(MySQL, PostgreSQL 등)를 직접 배포하는 대신, 클라우드 관리형 데이터베이스(RDS 등)를 우선 제안하되 Crossplane을 통해 선언적으로 생성할 것.
- **[MUST] CSI Drivers:** 기존 In-tree 스토리지 프로비저너 대신, 최신 CSI(Container Storage Interface) 드라이버 기반의 `StorageClass` 설정을 강제할 것.
- **[MUST] StatefulSet over Deployment:** 고정 네트워크 ID, 순차적 롤링 업데이트 및 영구 스토리지가 필요한 워크로드에는 `Deployment` 대신 `StatefulSet`을 사용할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Storage 및 볼륨 프로비저닝
- **[PREFER] Explicit Performance Parameters:** `StorageClass` 선언 시 맹목적으로 기본값을 사용하는 대신, 워크로드 요구사양에 맞게 `type`(예: `gp3`), `iopsPerGB`, `throughput` 파라미터를 명시적으로 기재할 것.
- **[MUST] Topology-Aware Volume Provisioning:** 멀티 AZ 환경의 영역 간 통신 요금 폭증 및 마운트 안정적 마운트 보장을 위해, `StorageClass` 내에 `volumeBindingMode: WaitForFirstConsumer` 설정을 반영해 파드가 스케줄링된 AZ와 동일한 위치에 볼륨을 생성하도록 하십시오.

### 2.2 상태 저장 워크로드 관리
- **[MUST] VolumeClaimTemplates:** 복수 Replica가 단일 볼륨을 동시에 쓰는 데이터 독립성을 보장하기 위해, `volumeClaimTemplates`를 선언하여 각 Replica가 독립적인 PV를 동적으로 할당받게 설계할 것.
- **[MUST] Stateful Anti-Affinity:** 데이터 고가용성 및 무결성 보장을 위해 StatefulSet 파드는 `podAntiAffinity` (topologyKey: `kubernetes.io/hostname` 및 `topology.kubernetes.io/zone`)를 적용하여 다중 노드 및 영역에 분산되도록 강제할 것.
- **[MUST] Ephemeral Storage Hard Limits:** 파드 내 `emptyDir` 사용 시 노드의 디스크 고갈(Disk Pressure) 환경에서도 안정성을 보장하도록 `limits.ephemeral-storage` 값을 명시적으로 지정할 것.

### 2.3 재해 복구(DR) 및 백업
- **[PREFER] Velero for Cluster DR:** K8s 리소스 YAML 메타데이터와 PV 스냅샷을 주기적으로 오브젝트 스토리지에 백업하고 복원하는 Velero 백업 아키텍처를 도입할 것.
- **[MUST] Application-Level Consistency:** PV 스냅샷 복구 시 DB 트랜잭션 무결성을 보장하도록 애플리케이션 레벨의 백업(예: `pg_dump`) 및 WAL(Write-Ahead Logging) 백업을 병행할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  iops: "3000"
```
</example>
<example>
[Bad]
```yaml
# volumeBindingMode: Immediate 설정 (파드가 없는 AZ에 볼륨이 먼저 선점되어 마운트 불가 위험)
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `StorageClass` 설정 내에 `volumeBindingMode`가 정확히 선언되고, 임시 스토리지 한계치(`ephemeral-storage`)가 할당된 매니페스트 문법 린트가 성공해야 합니다.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Stateful Applied] 점검 기준 (절차는 010-k8s-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (가용성): 볼륨 바인딩(WaitForFirstConsumer)과 Anti-Affinity가 결합되어 영역 장애 대응이 가능한가?
  - 기준 2 (데이터 정합성): 트랜잭션이 보장되는 복구 파이프라인(애플리케이션 백업 등)이 설계에 포함되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 파드 내에 `emptyDir: {}`가 선언되었으나 `limits.ephemeral-storage` 용량 상한선이 누락된 매니페스트가 감지될 시 즉시 작업을 중단(Halt & Clarify)하고 리소스 한계를 정의할 것.
  - StatefulSet 작성 시 `volumeClaimTemplates`가 누락되고 단일 PV를 여러 파드가 공유 마운트(`ReadWriteOnce`)하는 오류가 발견될 시 작업을 멈추고 설계를 즉각 변경할 것.
