---
name: drawio-gen
description: |
  인프라 및 시스템 아키텍처를 실제 .drawio XML로 생성·수정할 때 사용하는 스킬.
  AWS/Azure/OpenStack 토폴로지, draw.io XML 형식, 레이아웃·아이콘·가독성·검증 계약을 제공함.
---
# drawio-gen Skill

아키텍처 다이어그램(.drawio) 생성·수정에 사용한다. 일반 클라우드 설계 판단은 해당 클라우드 스킬/공식 문서를 따르고, 이 스킬에는 draw.io 산출물 계약만 둔다.

## 참조 라우팅

| 작업 유형 | 참조 문서 |
|---|---|
| DrawIO XML 공통 포맷·계층·엣지·라벨 | references/010-drawio-xml-standard.md |
| 좌표·크기·정렬·waypoint 계산 | references/015-layout-calculation-standard.md |
| AWS 아이콘 스타일 | references/020-aws-icon-style-library.md |
| Azure 아이콘 스타일 | references/030-azure-icon-style-library.md |
| OpenStack 아이콘·도형·색상 계약 | references/035-openstack-icon-style-library.md |
| OSS/서드파티 아이콘 | references/040-third-party-icon-library.md |
| 제목·범례·라벨·타이포그래피 | references/050-readability-standard.md |
| 완료 조건·기계 검증 | references/090-validation-standard.md |
| 레이아웃 계산·검증 구현 | scripts/layout_toolkit.py |

## 근거 계약

- IaC/리포지토리가 있으면 코드가 SSOT다. README·모듈 주석·Helm/values 등은 실제 운영 위치·워크로드를 보완하는 근거로만 사용한다.
- 주석 처리됐거나 실제 평가 결과가 비활성인 리소스는 배포된 것으로 그리지 않는다. 문서에 수동 운영 중이라고 명시된 경우에만 상태를 라벨로 표시해 포함한다.
- 자연어 설명만 있으면 사용자가 명시한 리소스 종류·수량을 그대로 반영한다. 미명시 세부사항을 채워야 하면 실제 리소스로 단정하지 말고 `(가정: ...)`으로 표시한다. 토폴로지 자체가 달라지는 모호성은 확인 없이 임의 확정하지 않는다.
- 코드와 설명이 충돌하면 코드를 덮어쓰지 말고 충돌을 드러낸다.
- 이 스킬의 산출물은 Cloud/Region/VPC·VNet·Neutron Network/Subnet/Resource 계층의 인프라 토폴로지다. 단순 폴더·리포지토리 구조도에는 사용하지 않는다.

## 산출물 계약

- 대상과 동일한 인프라의 기존 `.drawio`가 있으면 먼저 확인해 계층·아이콘·라벨 컨벤션을 상속한다.
- XML/아이콘/레이아웃/가독성 규칙은 위 참조 문서를 SSOT로 사용하고, 좌표는 가능한 한 `layout_toolkit.py` 헬퍼로 계산한다.
- 최종 산출물은 실제 `.drawio` 파일로 저장한다. 기본 위치는 대상 프로젝트 루트, 파일명은 대상·범위를 알 수 있는 kebab-case로 한다.
- HTML/SVG 등 별도 시각화 산출물은 사용자가 명시적으로 요청한 경우에만 만든다.

## 검증 계약

- 생성 직후 `python3 contexts/drawio-gen/scripts/layout_toolkit.py <file.drawio>`를 실행해 XML/ID/참조/겹침/정렬/라벨·범례 경고를 확인한다.
- matplotlib이 있으면 생성된 preview PNG를 열어 박스 정렬과 엣지 라우팅을 육안 확인한다. 서드파티 아이콘을 사용했고 네트워크가 가능하면 URL 검사도 수행한다.
- `layout_toolkit.py`, drawio reference, 테스트 계약을 수정했으면 `bash contexts/drawio-gen/tests/run.sh`를 실행한다.
