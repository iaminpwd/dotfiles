---
name: k8s
description: |
  Kubernetes(k8s) 클러스터 및 컨테이너 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI,
  PVC, StatefulSet, ArgoCD, Flux, Prometheus, Grafana, HPA, VPA, RBAC, OPA, 멀티테넌시.
  매니페스트 작성·검토, 클러스터 정책과 트러블슈팅에 사용.
  관리형 클러스터에서도 워크로드는 이 스킬로 다루고, 클라우드 IAM·노드·네트워크 변경이 있을 때만 클라우드 스킬을 추가 참조함.
  Pod Security Admission(PSA), securityContext, PrometheusRule 등 K8s CRD 및 어드미션 정책도 다룸.
---
# k8s Skill

이 스킬은 Kubernetes 관련 작업 시 발동됨.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 파드 / Deployment / ConfigMap 등 기본 K8s 리소스 작업 | references/010-k8s-core.md |
| 네트워크 리소스 (Ingress, Service, CNI) | references/020-networking-standard.md |
| 스토리지 (PVC/PV) 및 StatefulSet | references/030-storage-stateful-standard.md |
| CI/CD, GitOps (ArgoCD, Flux) | references/040-cicd-gitops-standard.md |
| Prometheus Operator CRD 수집 문법 (ServiceMonitor 등) | references/050-observability-standard.md |
| SLI/SLO, 알람 설계, 로깅, 분산 추적 등 관측성 일반 원칙 | `observability 스킬(SKILL.md)` (별도 스킬) |
| 오토스케일링 (HPA, VPA) 및 FinOps | references/060-autoscaling-finops-standard.md |
| 클러스터 보안 (RBAC, OPA, NetworkPolicy) | references/070-advanced-security-standard.md |
| 플랫폼 엔지니어링, 멀티테넌시 | references/080-platform-engineering-standard.md |
| K8s 장애 대응, 트러블슈팅, RCA | references/100-incident-response.md |

* 해당 주제의 설계·검토가 필요한 경우: references/010-k8s-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[PREFER] 필요한 참조 선택:** 라우팅 표에서 현재 작업에 해당하는 문서를 읽고, 연결된 문서는 판단에 필요한 경우에만 추가로 읽을 것. 이미 읽은 내용은 재사용할 것.
