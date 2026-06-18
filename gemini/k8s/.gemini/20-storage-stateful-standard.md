<k8s_storage_stateful_standard>
# 컨텍스트 모듈: Enterprise Kubernetes 스토리지, 상태 보존(Stateful) 워크로드 및 DR 표준

## 1. Storage 및 볼륨 프로비저닝 (Storage Provisioning)
- **[PREFER] Managed Database (via IaC/Crossplane):** K8s 클러스터 내부에 데이터베이스(MySQL, PostgreSQL, MongoDB 등)를 직접 띄우는 것을 지양하십시오. 가급적 AWS RDS 등 클라우드 관리형 데이터베이스를 사용하되, 이를 프로비저닝 할 때는 **Crossplane**이나 Terraform과 같은 IaC(Infrastructure as Code)를 통해 K8s 워크로드 배포와 생명주기를 맞추는 방식을 제안하십시오.
- **[MUST] CSI (Container Storage Interface) Drivers:** In-tree 스토리지 플러그인(K8s 코어에 포함된 과거 방식) 대신 최신 CSI 드라이버(EBS CSI, EFS CSI 등)를 활용한 StorageClass 설정을 표준으로 강제하십시오.
- **[MUST] Topology-Aware Volume Provisioning:** 멀티 AZ 클러스터에서는 파드가 스케줄링된 가용 영역(AZ)과 동일한 AZ에 클라우드 볼륨(EBS 등)이 생성되어야 합니다. StorageClass 작성 시 `volumeBindingMode: WaitForFirstConsumer`를 설정하여, 파드 스케줄링 전까지 볼륨 프로비저닝을 지연시키는 구성을 반드시 포함하십시오.

## 2. StatefulWorkload 관리 (StatefulSets)
- **[MUST] StatefulSet for Persistence:** 애플리케이션이 고유한 네트워크 식별자, 순차적 배포/종료 규칙, 전용 영구 볼륨(PV)이 필요한 경우 `Deployment` 대신 반드시 `StatefulSet`을 사용하십시오.
- **[MUST] VolumeClaimTemplates:** StatefulSet 내의 볼륨을 수동으로 PVC로 묶지 말고, 반드시 `volumeClaimTemplates`을 통해 각 파드 복제본(Replica)마다 고유한 PV가 동적으로 마운트되도록 구성하십시오.
- **[MUST] Anti-Affinity in StatefulSets:** 데이터 노드 파드 3개가 하나의 워커 노드에 몰려서 떠 있다가 노드가 다운되면 전체 장애가 발생합니다. `podAntiAffinity`를 설정하여 데이터 파드들이 서로 다른 노드나 가용 영역에 분산 배치되도록 강제하십시오.

## 3. 재해 복구(DR) 및 백업 (Disaster Recovery & Backup)
- **[MUST] Velero for Cluster DR:** K8s 클러스터 전면 장애 시 워크로드를 다른 클러스터로 이전하거나 복원하기 위해, K8s 리소스(YAML 상태)와 PV 스냅샷을 주기적으로 오브젝트 스토리지(S3 등)에 백업하는 **Velero** 솔루션 구성을 재해 복구 표준으로 제안하십시오.
- **[MUST] Application-Level Backup:** 영구 볼륨 스냅샷만으로는 데이터베이스의 메모리 상태나 트랜잭션 정합성(Consistency)을 보장할 수 없습니다. 단순히 Velero 스냅샷을 제안하는 것을 넘어, 데이터베이스 수준의 덤프(pg_dump 등)나 트랜잭션 로그 백업 아키텍처를 병행 제안하십시오.
- **[MUST] Ephemeral Storage Limits:** 임시 데이터 처리를 위해 파드의 `emptyDir`을 사용할 때, 무한정 데이터를 쌓아 워커 노드의 디스크 슬래시(`/`) 공간을 고갈(Disk Pressure)시키는 것을 막기 위해 `limits.ephemeral-storage`를 필수로 지정하도록 강제하십시오.
</k8s_storage_stateful_standard>
