---
name: k8s
description: |
  Kubernetes (K8s) 클러스터 및 오케스트레이션 스킬입니다. 다음 작업 유형에 따라 반드시 해당 references/ 하위 문서를 먼저 읽고 지침을 따르십시오:
  - 네트워크 리소스 설계 (Ingress, Service, CNI) -> references/020-networking-standard.md
  - 스토리지 (PVC/PV) 및 StatefulSet 관리 -> references/030-storage-stateful-standard.md
  - CI/CD 및 GitOps (ArgoCD, Flux) 배포 파이프라인 -> references/040-cicd-gitops-standard.md
  - 모니터링, 로깅 및 Observability (Prometheus, Grafana) -> references/050-observability-standard.md
  - 오토스케일링 (HPA, VPA) 및 FinOps 비용 최적화 -> references/060-autoscaling-finops-standard.md
  - 고급 클러스터 보안 (RBAC, OPA, NetworkPolicy) -> references/070-advanced-security-standard.md
  - 플랫폼 엔지니어링 및 멀티테넌시 -> references/080-platform-engineering-standard.md
  - K8s 장애 대응, 트러블슈팅(CrashLoopBackOff 등) 및 사후 분석(RCA) -> references/100-incident-response.md
  그 외 기본 K8s 코어 아키텍처는 010-k8s-core.md 참조.
---
# k8s Skill

이 스킬은 k8s 관련 작업 시 발동됩니다.
상세한 가이드라인 및 규칙은 `references/` 디렉토리 내부의 문서들을 참조하십시오.
