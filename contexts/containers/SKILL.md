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

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: Dockerfile이나 이미지 빌드 파이프라인 코드를 작성하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집할 것.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `pre-flight-check.sh` 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `~/dotfiles/contexts/pre-flight-check/SKILL.md`를 절대 경로로 읽어 동일 절차를 수행할 것.
