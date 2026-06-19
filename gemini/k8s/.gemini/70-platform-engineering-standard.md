<k8s_platform_engineering_standard>
# 컨텍스트 모듈: Enterprise Platform Engineering 및 최고급(Advanced) 아키텍처

## 1. 플랫폼 엔지니어링 (Platform Engineering & IDP)
- **[MUST] Developer Experience (DevEx) & Abstraction:** 애플리케이션 개발자는 비즈니스 로직에만 집중해야 합니다. K8s의 복잡성(Deployment, HPA, Ingress 등)을 개발자에게 날것의 YAML로 노출하지 마십시오. 사내 자체 Helm Chart나 Kustomize 템플릿(또는 KubeVela)을 통해 인터페이스를 추상화(Abstraction)하여 제공하십시오.
- **[PREFER] Internal Developer Platform (IDP):** 조직 규모가 크다면, 개발자가 CLI나 Git을 직접 다루기보다 **Backstage** 등 포털 UI에서 클릭만으로 파이프라인과 인프라를 셀프 서비스(Self-Service)로 프로비저닝하는 아키텍처 구성을 권장하십시오.

## 2. Multi-Cluster 및 Cloud-Native 제어 평면 (Control Plane)
- **[MUST] Fleet Management (Multi-Cluster):** 엔터프라이즈 환경에서는 단일 거대 클러스터보다 목적별/조직별 다수 클러스터(Multi-Cluster) 운영이 흔합니다. 클러스터 프로비저닝 시 **Cluster API (CAPI)**를 활용하여 인프라 생성 자체를 K8s 리소스로 선언(Declarative)하십시오. 멀티 클러스터 간 라우팅이 필요할 경우 Cilium Cluster Mesh를 제안하십시오.
- **[PREFER] Crossplane over Terraform:** 외부 클라우드 리소스(AWS RDS, S3 등) 프로비저닝 시, 외부 파이프라인의 Terraform 대신 **Crossplane**을 우선적으로 활용하십시오. K8s 클러스터 자체를 범용 제어 평면(Universal Control Plane)으로 삼아, 모든 인프라를 K8s CRD로 선언하고 ArgoCD의 통제 안에 두는 것이 최상위 프랙티스입니다.

## 3. Operator Pattern (오퍼레이터 패턴)
- **[MUST] Operator First for Stateful Apps:** Kafka, PostgreSQL, Redis 등 복잡한 데이터베이스나 미들웨어를 K8s에 올릴 때, 원시(Raw) StatefulSet을 직접 작성하는 것을 지양하십시오. 백업, 복구, 스케일링 등 Day 2 운영 지식이 코드로 구현되어 있는 해당 벤더의 **Operator (예: Strimzi, Zalando Postgres Operator)** 도입을 무조건 첫 번째 대안으로 제시하십시오.

## 4. 복원력 검증 (Resilience & Chaos Engineering)
- **[PREFER] Chaos Engineering:** 프로덕션 환경의 실제 안정성을 증명하기 위해 **LitmusChaos** 또는 **Chaos Mesh**를 도입하여 파드 무작위 종료, 네트워크 지연 주입(Fault Injection) 테스트를 정기적으로 수행하는 문화를 제안하십시오. (단, 인프라 성숙도가 충분한 경우에만 제안)
- **[PREFER] Blameless Post-mortem:** 장애 발생 시 자동화된 Runbook(Jupyter Notebook for SRE 등)을 K8s 생태계에 연동하는 관점을 답변에 포함하십시오.
</k8s_platform_engineering_standard>
- **[Trigger: User requests bug fix or error analysis] 분석 결과 구조화 (Structured Analysis):**
  > When reviewing errors, do not simply throw code into the chat. You MUST document the analysis results in a dedicated `troubleshooting-report.md` artifact file in the following order: 1. Root Cause Analysis, 2. Logical Basis, 3. Step-by-Step Solution & Modified Code, 4. Prevention Plan (Best Practice).

