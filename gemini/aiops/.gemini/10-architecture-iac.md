<aiops_architecture_iac>
# Enterprise IaC & GitOps 아키텍처 표준

## 1. 엔터프라이즈 배포 및 상태(State) 관리 원칙
- **[MUST] GitOps First:** 단순 스크립트 실행을 넘어, GitHub Actions, ArgoCD, Flux 등을 활용한 GitOps 기반의 배포 파이프라인 설계를 최우선으로 제안하십시오.
- **[MUST] State Locking & Isolation:** Terraform 등 IaC 작성 시, 단일 장애점(SPOF)을 막기 위해 S3 Backend와 DynamoDB를 통한 State 잠금(Locking) 체계를 반드시 포함하고, 개발/운영 환경을 완벽히 격리(Isolation)하십시오.
- **[Trigger: IaC Deployment Completion] IaC Deployment Summary:** IaC 기반의 인프라 배포가 완료되면, 반드시 상태 변경 내역(Drift)을 `iac-deployment-summary.md` 산출물로 문서화하십시오.

## 2. 고가용성 및 복원력(Resiliency) 설계
- **[PREFER] Stateless Over Stateful:** 시스템 복원력을 극대화하기 위해 컨테이너나 워크로드는 가급적 상태(State)를 가지지 않도록 설계(Stateless)하고, 상태 관리는 외부 관리형 데이터베이스나 캐시로 완전히 위임하는 아키텍처를 우선 제안하십시오.
- **[PREFER] Immutable Infrastructure:** 리소스 구성 변경 시 기존 리소스를 직접 수정(Mutable)하는 대신, 새로운 리소스를 배포하고 트래픽을 전환한 뒤 이전 리소스를 폐기하는 불변 인프라(Immutable) 패턴을 우선 제안하십시오.
- **[MUST] Multi-AZ & DR:** 단일 가용 영역(AZ) 장애에 대비한 Multi-AZ 아키텍처를 기본으로 구성하며, 주요 데이터는 RTO(복구 목표 시간)와 RPO(복구 목표 시점)를 충족할 수 있도록 스냅샷/백업 정책을 명시하십시오.
- **[MUST] Dead Letter Queue (DLQ):** EventBridge, SQS, SNS 등 이벤트 기반 비동기 통신 구간에는 반드시 DLQ를 연동하여, 처리 실패한 이벤트가 영구 유실되지 않고 추후 재처리(Replay) 가능하도록 구성해야 합니다.

## 3. 명명 규칙 (Naming Convention)
- **[MUST] Naming Standard:** 시스템 아키텍처나 파이프라인 리소스를 제안할 때는 모호한 표현을 피하고, `<Project>-<Env>-<Service>-<Resource>` 형태의 직관적이고 표준화된 엔터프라이즈 명명 규칙을 사용하십시오.
</aiops_architecture_iac>
