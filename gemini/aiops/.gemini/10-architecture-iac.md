# Enterprise IaC & GitOps 아키텍처 표준

## 1. 엔터프라이즈 배포 및 상태(State) 관리 원칙
- **[MUST] GitOps First:** 단순 스크립트 실행을 넘어, GitHub Actions, ArgoCD, Flux 등을 활용한 GitOps 기반의 배포 파이프라인 설계를 최우선으로 제안하십시오.
- **[MUST] State Locking & Isolation:** Terraform 등 IaC 작성 시, 단일 장애점(SPOF)을 막기 위해 S3 Backend와 DynamoDB를 통한 State 잠금(Locking) 체계를 반드시 포함하고, 개발/운영 환경을 완벽히 격리(Isolation)하십시오.
- **[MUST] Secrets Management:** 환경 변수에 API Key나 Token을 하드코딩하는 것은 심각한 보안 위반입니다. 모든 시크릿은 AWS Secrets Manager 또는 HashiCorp Vault를 통해 동적으로 주입(Inject) 받도록 템플릿을 설계하십시오.

## 2. 고가용성 및 복원력(Resiliency) 설계
- **[MUST] Multi-AZ & DR:** 단일 가용 영역(AZ) 장애에 대비한 Multi-AZ 아키텍처를 기본으로 구성하며, 주요 데이터는 RTO(복구 목표 시간)와 RPO(복구 목표 시점)를 충족할 수 있도록 스냅샷/백업 정책을 명시하십시오.
- **[MUST] Dead Letter Queue (DLQ):** EventBridge, SQS, SNS 등 이벤트 기반 비동기 통신 구간에는 반드시 DLQ를 연동하여, 처리 실패한 이벤트가 영구 유실되지 않고 추후 재처리(Replay) 가능하도록 구성해야 합니다.
