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

Kubernetes 작업에 사용한다. 일반 K8s 설계·운영 지식은 현재 코드와 공식 문서를 기준으로 판단한다. SLI/SLO·알람 정책·로깅·분산 추적의 일반 기준은 `contexts/observability/SKILL.md`에 위임한다.

## 저장소 검증 계약

- K8s/Helm/정책 검증 로직을 변경하면 `bash contexts/k8s/tests/run.sh`를 실행한다.
- `kube-linter`의 `privileged-container` 체크, `promtool`의 PrometheusRule 문법 검사, `pluto`의 deprecated/removed API 검출, `kyverno test` 결과를 회귀로 고정한다.
- `bin/hooks/plugins/k8s-check.sh`는 스테이징 대상만 검사하며 PrometheusRule 멀티 도큐먼트의 뒤쪽 규칙까지 검증하고, Pluto 스캔은 대상 매니페스트만 임시 디렉토리에 격리한다.
- Helm은 루트 차트와 explicit-file 모드 모두 lint 대상이어야 한다. Conftest 정책 수집 시 `tests/fixtures*` 아래 정책은 실검증에서 제외하되 실제 정책은 계속 강제한다.
- 회귀 테스트에 필요한 도구가 없으면 실패한다. YAML 다중 문서 처리에서 불필요한 `yq` 반복 호출을 만들지 않는다.
- `kubectl delete namespace`, `kubectl delete deployment --all` 같은 광역 삭제는 리소스명·라벨 셀렉터 등 대상 범위를 명시적으로 검증한 경우에만 실행한다.
- 실제 변경 파일의 quick/full 검사와 WARNING/SKIP 해석은 `contexts/pre-flight-check/SKILL.md`를 따른다.
