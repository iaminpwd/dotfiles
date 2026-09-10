---
name: containers
description: |
  컨테이너 이미지 엔지니어링 스킬. Dockerfile/OCI 이미지 빌드, 멀티스테이지,
  이미지 하드닝(non-root, distroless), SBOM/서명/취약점 스캔 등 공급망 보안,
  레지스트리 태깅 및 라이프사이클, 컨테이너 런타임 트러블슈팅.
---
# containers Skill

이 스킬은 Dockerfile 작성, 컨테이너 이미지 빌드/하드닝, 공급망 보안, 레지스트리 관리 작업 시 발동됨. K8s 오케스트레이션 자체(매니페스트, HPA 등)는 `k8s` 스킬을 참조할 것.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| Dockerfile 작성 및 멀티스테이지 빌드 | references/010-containers-core.md |
| 이미지 하드닝 (non-root, distroless, RO rootfs) | references/020-image-hardening-standard.md |
| SBOM, 이미지 서명, 취약점 스캔 (공급망 보안) | references/030-supply-chain-security-standard.md |
| 레지스트리 태깅 규칙 및 라이프사이클 정책 | references/040-registry-lifecycle-standard.md |
| 컨테이너 런타임 장애 대응 (OOMKilled, CrashLoop 등) | references/100-incident-response.md |

* **기본 컨테이너 코어 원칙**: references/010-containers-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[PREFER] 필요한 참조 선택:** 라우팅 표에서 현재 작업에 해당하는 문서를 읽고, 연결된 문서는 판단에 필요한 경우에만 추가로 읽을 것. 이미 읽은 내용은 재사용할 것.
