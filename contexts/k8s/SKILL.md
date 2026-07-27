---
name: k8s
description: |
  Kubernetes 클러스터 및 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI,
  PVC, StatefulSet, ArgoCD, Flux, Prometheus, Grafana, HPA, VPA, RBAC, OPA, 멀티테넌시.
  관리형 클러스터(EKS, AKS, GKE, Magnum) 위에서 워크로드·권한·정책·네트워킹을 다루는
  작업까지 포함하며, 이때는 클러스터를 제공하는 클라우드 쪽 스킬도 같이 필요합니다.
  Pod Security Admission(PSA), securityContext, PrometheusRule 등 K8s CRD 및 어드미션
  정책 관련 질문도 여기서 다룹니다.
reviewed: 2026-07-27
---
# k8s Skill

이 스킬은 Kubernetes 관련 작업 시 발동됩니다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 파드 / Deployment / ConfigMap 등 기본 K8s 리소스 작업 | references/010-k8s-core.md |
| 네트워크 리소스 (Ingress, Service, CNI) | references/020-networking-standard.md |
| 스토리지 (PVC/PV) 및 StatefulSet | references/030-storage-stateful-standard.md |
| CI/CD, GitOps (ArgoCD, Flux) | references/040-cicd-gitops-standard.md |
| Prometheus Operator CRD 수집 문법 (ServiceMonitor 등) | references/050-observability-standard.md |
| SLI/SLO, 알람 설계, 로깅, 분산 추적 등 관측성 일반 원칙 | `~/dotfiles/contexts/observability/SKILL.md` (별도 스킬) |
| 오토스케일링 (HPA, VPA) 및 FinOps | references/060-autoscaling-finops-standard.md |
| 클러스터 보안 (RBAC, OPA, NetworkPolicy) | references/070-advanced-security-standard.md |
| 플랫폼 엔지니어링, 멀티테넌시 | references/080-platform-engineering-standard.md |
| K8s 장애 대응, 트러블슈팅, RCA | references/100-incident-response.md |

* **기본 K8s 코어 아키텍처**: references/010-k8s-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 인프라 코드(매니페스트, Helm Chart 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `pre-flight-check.sh` 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `~/dotfiles/contexts/pre-flight-check/SKILL.md`를 절대 경로로 읽어 동일 절차를 수행하십시오.
