---
name: containers
description: |
  컨테이너 이미지 엔지니어링 스킬. Dockerfile/OCI 이미지 빌드, 멀티스테이지,
  이미지 하드닝(non-root, distroless), SBOM/서명/취약점 스캔 등 공급망 보안,
  레지스트리 태깅 및 라이프사이클, 컨테이너 런타임 트러블슈팅.
---
# containers Skill

Dockerfile/OCI 이미지 작업 시 사용한다. Kubernetes 매니페스트와 오케스트레이션은 `k8s` 스킬을 사용한다.

## 저장소 검증 계약

- 일반 Docker/OCI 설계 지식은 여기서 재서술하지 않는다. 현재 코드와 공식 문서를 기준으로 판단한다.
- Dockerfile/컨테이너 검증 로직을 변경하면 `bash contexts/containers/tests/run.sh`를 실행한다.
- `tests/run.sh`는 `hadolint`의 unpinned-base `DL3007`, `trivy`의 root-user `DS-0002`, `bin/linters/container-hardening-gate.sh`의 DS-0002 차단과 스캐너 실패 시 false-green 방지를 고정한다.
- `trivy` misconfig 검사는 pre-flight에서 경고 신호이고, `container-hardening-gate.sh`는 커밋 중단 게이트다. 둘을 같은 판정 강도로 취급하지 않는다.
- 도구 미설치·실행 실패는 해당 회귀 테스트에서 실패다. `tests/fixtures/`는 의도적인 위반 샘플이라 전체 저장소 보안 스캔에서 제외되며, 실제 시크릿 fixture는 두지 않는다.
- 변경 파일의 quick/full 검사와 WARNING/SKIP 해석은 `contexts/pre-flight-check/SKILL.md`를 따른다.
