---
name: k8s
description: |
  Kubernetes 클러스터 및 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI,
  PVC, StatefulSet, ArgoCD, Flux, Prometheus, Grafana, HPA, VPA, RBAC, OPA, 멀티테넌시.
---
# k8s Skill

이 스킬은 Kubernetes 관련 작업 시 발동됩니다.

## 작업 유형별 참조 문서 라우팅

| 작업 유형 | 참조 문서 |
|-----------|----------|
| 네트워크 리소스 (Ingress, Service, CNI) | references/020-networking-standard.md |
| 스토리지 (PVC/PV) 및 StatefulSet | references/030-storage-stateful-standard.md |
| CI/CD, GitOps (ArgoCD, Flux) | references/040-cicd-gitops-standard.md |
| 모니터링, Observability (Prometheus, Grafana) | references/050-observability-standard.md |
| 오토스케일링 (HPA, VPA) 및 FinOps | references/060-autoscaling-finops-standard.md |
| 클러스터 보안 (RBAC, OPA, NetworkPolicy) | references/070-advanced-security-standard.md |
| 플랫폼 엔지니어링, 멀티테넌시 | references/080-platform-engineering-standard.md |
| K8s 장애 대응, 트러블슈팅, RCA | references/100-incident-response.md |

기본 K8s 코어 아키텍처: references/010-k8s-core.md

## [MUST] 매니페스트/Helm 코드 수정 후 필수 후속 동작

K8s 매니페스트, Helm Chart, ArgoCD Application 등 인프라 코드를 신규 작성하거나 수정한 경우, **작업 완료를 선언하기 전에** 반드시 아래 절차를 따르십시오.

1. `Pre-Flight Check` 스킬의 `SKILL.md`를 `view_file` 도구로 직접 읽으십시오.
2. 해당 SKILL.md에 명시된 `pre-flight-check.sh` 복사 및 실행 절차를 그대로 수행하십시오.
