---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Kubernetes, AKS, Helm, or container orchestration.
---
# 컨텍스트 모듈: Kubernetes (AKS) 특화 표준

## 1. 클러스터 보안 및 인증 (Security & Auth)
- **[MUST] Least Privilege (Workload Identity):** AKS 워크로드(Pod)에 권한을 부여할 때 반드시 Azure Workload Identity를 적용하여 최소 권한을 달성하십시오.
- **[MUST] Envelope Encryption:** K8s Secret은 반드시 Azure Key Vault(AKV)와 연동한 봉투 암호화(Envelope Encryption)를 적용하여 안전하게 저장되도록 구성하십시오.
- **[PREFER] Node Security:** 노드 풀(Agent Node)의 보안 강화를 위해 컨테이너에 최적화된 Azure Linux 컨테이너 호스트 사용을 우선 제안하십시오.

## 2. 공통 K8s 코어 룰 참조 (Lazy Routing)
- **[MUST] Reference Generic K8s Rules:** 쿠버네티스 공통 기능(네트워크, 스토리지, 파드 생명주기, GitOps 등) 작업 시, 현재 폴더에 지식이 없다면 반드시 **`../../k8s/SKILL.md`** 파일을 가장 먼저 읽고(View), 그 안에 명시된 라우팅 가이드(description)에 따라 `references/` 하위의 적절한 코어 룰을 찾아 팩트를 수집한 뒤 작업하십시오.
