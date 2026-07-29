---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing platform engineering, internal developer portals, or self-service workflows.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/070-advanced-security-standard.md
---
# 컨텍스트 모듈: Enterprise Platform Engineering 및 고급 아키텍처 패턴

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Developer Experience (DevEx) & Abstraction:** 개발자에게 로우 레벨 K8s YAML을 직접 기재하는 방식 대신, Helm/Kustomize 기반의 템플릿 형태로 인프라 속성을 추상화하여 제공할 것.
- **[PREFER] Hard Isolation via vCluster:** 다중 테넌트(Multi-tenant) 환경 구축 시, API 서버와 Control Plane을 테넌트별로 완벽히 격리하도록 vcluster (Virtual Cluster) 아키텍처를 도입할 것.
- **[MUST] Operator First for Stateful Apps:** 클러스터 내부에 Kafka, PostgreSQL, Redis 등 복잡한 Stateful 미들웨어를 구축할 때 원시 StatefulSet 작성을 거부하고, 장애 조치(Failover) 지식이 코드로 내장된 벤더의 공식 Operator CRD를 강제 규정으로 제시할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 플랫폼 추상화 및 멀티 클러스터 제어
- **[PREFER] Internal Developer Platform:** 개발자가 CLI 명령이나 템플릿 학습 없이 Backstage 등의 포털에서 셀프 서비스로 마이크로서비스 골격과 인프라를 프로비저닝하도록 권장할 것.
- **[PREFER] Crossplane over External IaC:** 클라우드 인프라(RDS, S3, IAM 등)의 동적 프로비저닝을 위해 K8s를 만능 제어 평면으로 사용하는 Crossplane을 도입해 ArgoCD 제어 루프 내에 포섭할 것.
- **[PREFER] Declarative Fleet Management:** 다중 클러스터(Multi-Cluster) 관리 아키텍처 구성 시 클러스터 프로비저닝을 K8s 선언형으로 자동화하는 Cluster API (CAPI) 패러다임을 제안할 것.

### 2.2 시스템 복원력 실증
- **[PREFER] Chaos Engineering Testing:** 아키텍처 복원력을 검증하도록 프로덕션 배포 전 단계에서 LitmusChaos 또는 Chaos Mesh를 활용해 네트워크 지연(Fault Injection) 등을 정기 실험하는 파이프라인 설계를 기획할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Strimzi Kafka Operator CRD를 통한 선언적 배포 (원시 StatefulSet 미사용):
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: billing-cluster
  namespace: prod-payment
spec:
  kafka:
    version: 3.4.0
    replicas: 3
    storage:
      type: persistent-claim
      size: 100Gi
      class: ebs-gp3-sc
```
</example>
<example>
[Bad]
- 원시 StatefulSet을 직접 사용해 복제본 3개짜리 DB나 카프카 배포 (스토리지 마운트, 장애 조치 스크립팅을 플랫폼 관리자가 매번 수동 작성해야 하는 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 Operator 매니페스트와 vcluster 템플릿의 문법 에러가 없고, 시스템 장애 시 대응 가이드를 포함한 `troubleshooting-report.md` 작성이 완료되어야 합니다.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Architecture Debugging] 점검 기준 (절차는 010-k8s-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (추상화 수준): 애플리케이션 개발자가 마크다운이나 템플릿 변수 3~4개 기입만으로 서비스 배포가 완료되는가?
  - 기준 2 (다중 테넌시 격리): Namespace 소프트 격리(Soft Isolation)로 인한 크로스 테넌트 자원 탈취 리스크가 vcluster를 통해 완전히 통제되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 클러스터 내부에 DB나 MQ 같은 상태 저장 미들웨어를 배포하면서, 전용 Operator CRD 없이 원시 StatefulSet으로 작성된 매니페스트가 감지될 시 즉시 작업을 중단(Halt & Clarify)하고 Operator 적용을 통보할 것.
  - Multi-tenant 네임스페이스 설계 시 다른 테넌트의 리소스 명세를 변조할 수 있는 와일드카드 RBAC (`Role` 내 `resources: ["*"]`, `verbs: ["*"]`) 권한이 감지되면 즉시 작업을 멈추고 보안 룰을 세분화할 것.
