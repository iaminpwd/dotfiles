---
name: pre-flight-check
description: |
  이 저장소의 pre-flight 검증 대상, 프로필, 실행 명령과 WARNING/SKIP/실패 결과를 해석할 때 사용하는 로컬 스킬.
---
# pre-flight-check Skill

실행 로직의 SSOT는 `bin/hooks/pre-flight-check.sh`, 공용 검증 구현은 `bin/lib/pfc-*.sh`와 `bin/hooks/plugins/*.sh`다. 이 문서에는 호출 계약과 결과 해석만 둔다.

## 대상 선택

- 인자 없음: staged 파일만 검사한다.
- `--changed`: staged + unstaged + untracked 변경 파일을 검사한다.
- `--all`: tracked + untracked 파일 전체를 검사한다.
- 파일 경로 직접 지정: 지정 파일만 대상 선택에 사용하며, 존재하지 않는 경로는 실패한다.
- 회귀용 `tests/fixtures*`는 의도적 위반을 포함할 수 있어 전역 대상에서 제외한다.

## 프로필

- `PFC_PROFILE=quick`: shell/YAML/Dockerfile과 Terraform fmt를 빠르게 검사한다. 전체 인프라 검증 통과를 의미하지 않는다.
- `PFC_PROFILE=stop`: quick 범위에 Ansible 검사를 더한다. Stop 훅의 변경 파일 검증에 사용된다.
- `PFC_PROFILE=full`(기본): shell/Ansible/Dockerfile/YAML/보안 검사를 실행한다.
- full에서 Terraform validate, SAM, Helm, Kubernetes, Conftest, FinOps, delegated plugin까지 실행하려면 `PFC_DOMAIN_CHECKS=1`을 추가한다.

## 저장소 명령

- 변경 파일 검사: `bash bin/hooks/pre-flight-check.sh --changed`
- 저장소 전체 기본 검사: `just check`
- 인프라·도메인 정책까지 포함: `just check-domain`
- 변경 영역 회귀: `just check-changed`
- pre-flight + 전체 스킬 회귀 + prompt-lint: `just verify`
- pre-flight 공용 로직 회귀: `bash contexts/pre-flight-check/tests/run.sh`

## 결과 해석

- 종료 코드가 비정상이면 실패다. 일부 러너는 다른 검사를 계속 실행하므로 마지막 요약과 최종 종료 코드를 함께 확인한다.
- `[WARNING]` 또는 도구 미설치/비활성화 메시지는 검증 범위가 줄었다는 뜻일 수 있다. exit 0만 보고 해당 검사가 수행됐다고 보고하지 않는다.
- staged/changed/all 모드의 대상이 0건이면 경고가 날 수 있다. 이 경우 실제 검증 대상이 있었는지 확인한다.
- quick/stop 통과를 full 또는 domain 검사 통과로 확대 해석하지 않는다.
- 실패 로그는 원인을 수정한 뒤 같은 대상과 프로필로 재실행한다. 훅이나 검증기를 우회해 성공으로 만들지 않는다.
