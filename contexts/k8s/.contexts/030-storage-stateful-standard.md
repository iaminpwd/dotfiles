---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing stateful workloads, PVs, or cluster DR backups.
---
# 컨텍스트 모듈: Enterprise Kubernetes 스토리지, 상태 보존(Stateful) 워크로드 및 DR 표준

## 1. Storage 및 볼륨 프로비저닝 (Storage Provisioning)
- **[PREFER] Managed Database Delegation:** 클러스터 내부에 데이터베이스(MySQL, PostgreSQL 등)를 직접 대신 관리형 서비스를 우선 제안하십시오. 데이터 정합성 보장을 위해 AWS RDS 등 클라우드 관리형 데이터베이스 사용을 원칙으로 하되, **Crossplane**이나 Terraform을 통해 K8s 내부에서 관리형 인프라를 프로비저닝하는 선언적 패턴을 우선 제안하십시오.
- **[MUST] CSI (Container Storage Interface) Drivers:** In-tree 스토리지 최신 CSI 기반 설정을 강제하십시오. 반드시 최신 CSI 드라이버(EBS CSI, EFS CSI 등) 기반의 `StorageClass` 설정을 표준으로 강제하십시오.
- **[MUST] Explicit Performance Parameters:** `StorageClass` 선언 시 맹목적인 기본값 사용을 대신, 엔터프라이즈 워크로드 요구사항에 맞게 `type` (예: `gp3`), `iopsPerGB`, `throughput` 파라미터를 명시적으로 할당하십시오.
- **[MUST] Topology-Aware Volume Provisioning:** 멀티 AZ 클러스터에서는 파드가 스케줄링된 가용 영역(AZ)과 동일한 위치에 볼륨이 생성되어야 합니다. 반드시 `volumeBindingMode: WaitForFirstConsumer`를 설정하여 파드 스케줄링 전까지 프로비저닝을 지연(Lazy Provisioning)시키십시오.

## 2. StatefulWorkload 관리 (StatefulSets)
- **[MUST] StatefulSet over Deployment:** 순차적 식별자, 정렬된 롤링 업데이트, 고정된 네트워크 ID, 영구 스토리지가 필요한 워크로드에는 `Deployment`가 아닌 `StatefulSet`을 반드시 사용하십시오.
- **[MUST] VolumeClaimTemplates:** 동적 프로비저닝을 강제하십시오. 반드시 `volumeClaimTemplates`를 사용하여 Replica마다 고유한 독립적 PV가 동적으로 프로비저닝되도록 아키텍처를 구성하십시오.
- **[MUST] Stateful Anti-Affinity:** 데이터 파드가 단일 노드나 단일 AZ에 몰려 단일 장애점(SPOF)이 되는 것을 막기 위해, `podAntiAffinity` (topologyKey: `kubernetes.io/hostname` 및 `topology.kubernetes.io/zone`) 구성을 강제하십시오.

## 3. 재해 복구(DR) 및 백업 (Disaster Recovery)
- **[MUST] Velero for Cluster DR:** 클러스터 전면 장애에 대비하여 K8s 메타데이터(YAML)와 PV 스냅샷을 주기적으로 오브젝트 스토리지(S3 등)에 백업 및 복원하는 **Velero** 솔루션을 DR 표준으로 제시하십시오.
- **[MUST] Application-Level Consistency:** PV 스냅샷만으로는 메모리에 상주하는 데이터 트랜잭션의 정합성을 보장할 수 없습니다. 데이터베이스 워크로드의 경우, 애플리케이션 레벨의 덤프 로직(예: `pg_dump`)이나 WAL(Write-Ahead Logging) 백업 파이프라인을 병행 설계하십시오.
- **[MUST] Ephemeral Storage Hard Limits:** 파드에서 `/tmp` 등 임시 데이터를 저장하기 위해 `emptyDir`을 사용할 때, 노드의 디스크를 고갈(Disk Pressure)시키는 현상을 방지하기 위해 `limits.ephemeral-storage` 값을 명시적으로 할당하십시오.
</k8s_storage_stateful_standard>
