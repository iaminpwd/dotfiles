---
name: k8s
description: |
  Kubernetes 클러스터 및 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI,
  PVC, StatefulSet, ArgoCD, Flux, Prometheus, Grafana, HPA, VPA, RBAC, OPA, 멀티테넌시.
---
# k8s Skill

이 스킬은 Kubernetes 관련 작업 시 발동됩니다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 네트워크 리소스 (Ingress, Service, CNI) | references/020-networking-standard.md |
| 스토리지 (PVC/PV) 및 StatefulSet | references/030-storage-stateful-standard.md |
| CI/CD, GitOps (ArgoCD, Flux) | references/040-cicd-gitops-standard.md |
| 모니터링, Observability (Prometheus, Grafana) | references/050-observability-standard.md |
| 오토스케일링 (HPA, VPA) 및 FinOps | references/060-autoscaling-finops-standard.md |
| 클러스터 보안 (RBAC, OPA, NetworkPolicy) | references/070-advanced-security-standard.md |
| 플랫폼 엔지니어링, 멀티테넌시 | references/080-platform-engineering-standard.md |
| K8s 장애 대응, 트러블슈팅, RCA | references/100-incident-response.md |

* **기본 K8s 코어 아키텍처**: references/010-k8s-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 분석**: 인프라 코드(매니페스트, Helm Chart 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 `view_file`로 먼저 읽어 아키텍처 표준을 파악하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 반드시 [Pre-Flight Check SKILL.md](file:///home/ubuntu/dotfiles/contexts/pre-flight-check/SKILL.md)를 읽고 `pre-flight-check.sh` 스크립트를 실행하여 정량 검증을 완료하십시오.
