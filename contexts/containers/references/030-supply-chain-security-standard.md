---
role: Senior Container Security Engineer
priority: high
trigger: Apply these rules ONLY when generating SBOMs, signing images, or gating builds on vulnerability scan results.
references:
  - contexts/containers/references/010-containers-core.md
reviewed: 2026-07-21
---
# 컨테이너 공급망 보안 표준 (Supply Chain Security)

본 모듈은 SBOM 생성, 이미지 서명, 취약점 스캔 게이팅 등 소프트웨어 공급망 무결성 확보 시 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] SBOM Mandatory:** 프로덕션에 배포되는 모든 이미지는 빌드 파이프라인에서 SBOM(Software Bill of Materials)을 생성하여 이미지와 함께 보관하십시오.
- **[MUST] Signed Images Only:** 프로덕션 배포 대상 이미지는 반드시 서명하고, 배포 클러스터에서는 서명 검증을 통과한 이미지만 허용하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 SBOM 및 취약점 스캔
- **[MUST] SBOM Generation:** `syft <image> -o spdx-json` 등으로 이미지 빌드 직후 SBOM을 생성하고 아티팩트로 보관하십시오.
- **[MUST] CVE Gating:** `trivy image` 또는 `grype`로 CRITICAL 등급 취약점을 스캔하고, 승인된 예외(Ignore File)가 없는 CRITICAL 취약점이 발견되면 파이프라인을 중단하십시오.
- **[PREFER] Dual-Scanner Cross-Check:** 단일 스캐너의 미탐(False Negative)을 보완하기 위해, 릴리즈 이미지에는 `trivy`와 `grype` 두 스캐너 결과를 교차 확인하십시오.

### 2.2 서명 및 출처 증명
- **[MUST] Cosign Signing:** 이미지 푸시 직후 `cosign sign --key <key_ref> <image_digest>`로 서명하십시오. 태그가 아닌 다이제스트(digest) 기준으로 서명하여 태그 재사용 공격을 방지하십시오.
- **[MUST] Verify Before Deploy:** 배포 파이프라인 진입 전 `cosign verify --key <key_ref> <image_digest>`로 서명을 검증하고, 검증 실패 시 배포를 즉시 차단하십시오.
- **[PREFER] SLSA Provenance:** CI 파이프라인에서 빌드 출처(누가, 어떤 커밋으로, 어떤 빌더로 만들었는지) 증명을 위해 SLSA Provenance를 첨부하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```bash
IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' myapp:v1.2.3)
syft "$IMAGE_DIGEST" -o spdx-json > sbom.json
trivy image --severity CRITICAL --exit-code 1 "$IMAGE_DIGEST"
cosign sign --key cosign.key "$IMAGE_DIGEST"
```
</example>
<example>
[Bad]
```bash
docker push myapp:latest
# SBOM 생성 없음, 취약점 스캔 없음, 서명 없음 -> 공급망 출처 추적 불가
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** SBOM 파일이 생성되어 아티팩트로 보관되고, CRITICAL 취약점 없이 이미지 서명이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** `syft`, `trivy image`, `grype`, `cosign verify`를 실행하여 SBOM/취약점/서명 상태를 각각 팩트로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Image Pushed to Registry] 점검 기준 (절차는 010-containers-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (추적성): SBOM이 생성되어 이미지의 구성 요소가 완전히 추적 가능한가?
  - 기준 2 (무결성): 이미지가 다이제스트 기준으로 서명되고 배포 전 검증 경로가 존재하는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `trivy` 또는 `grype` 스캔 결과 CRITICAL 등급 취약점이 발견되었으나 승인된 예외 처리(Ignore File)가 없을 경우 즉시 배포를 중단(Hard Block)하십시오.
  - `cosign verify`가 실패하거나 서명 자체가 부재한 이미지가 프로덕션 배포 대상으로 지정될 경우 즉시 작업을 멈추고 서명 절차를 요구하십시오.
