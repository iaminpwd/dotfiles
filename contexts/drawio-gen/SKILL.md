---
name: drawio-gen
description: |
  아키텍처 다이어그램 생성 스킬. "다이어그램 그려줘", "구성도 만들어줘", "도식화해줘",
  "시각화해줘", ".drawio 로 정리해줘" 같은 요청에 사용하십시오.
  입력은 IaC 코드(Terraform, CloudFormation, Bicep/ARM, Heat HOT) 또는 자연어 아키텍처
  설명(예: "EKS 2개와 NAT Gateway를 쓴다") 둘 다 가능하며,
  AWS · Azure · OpenStack 아키텍처 다이어그램(.drawio XML)을 산출합니다.
  그리려는 대상이 특정 클라우드라면 그 클라우드 쪽 스킬도 같이 필요합니다.
reviewed: 2026-07-27
---
# drawio-gen Skill

이 스킬은 사용자가 IaC 코드 또는 자연어 아키텍처 설명과 함께 아키텍처 다이어그램/drawio 생성을 요청할 때 발동됩니다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 근거 충실성 원칙 (Anti-Hallucination) | references/005-fidelity-anti-hallucination-standard.md |
| DrawIO XML 공통 포맷 규격 | references/010-drawio-xml-standard.md |
| 레이아웃 계산 및 배치 검증 (좌표/크기/정렬/waypoint) | references/015-layout-calculation-standard.md |
| AWS 리소스 아이콘 스타일 | references/020-aws-icon-style-library.md |
| Azure 리소스 아이콘 스타일 | references/030-azure-icon-style-library.md |
| OpenStack 리소스 아이콘 스타일 | references/035-openstack-icon-style-library.md |
| 서드파티/OSS 도구 아이콘 (클라우드 공통) | references/040-third-party-icon-library.md |
| 가독성 (범례/제목/라벨 줄바꿈/타이포그래피) | references/050-readability-standard.md |
| 검증 및 수락 기준 (완료 조건/검증 스크립트) | references/090-validation-standard.md |
| 레이아웃 계산 공용 코드 (격자/스택/겹침검사) | ~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py |

## 2. 생성 프로세스 (6단계)

| 단계 | 작업 | 상세 |
|---|---|---|
| 0 | 입력 모드 판별 | 사용자가 IaC 코드/리포지토리를 제공했는지, 자연어 설명만 제공했는지 판별(005 §0). 두 방식이 섞이면 코드를 SSOT로 하고 설명은 보완 근거로만 사용 |
| 1 | 근거 수집 | **코드 기반**: 파일 검색·조회로 모든 리소스 정의 전수 수집. **설명 기반**: 사용자 발화에서 리소스 종류·수량·구성 힌트를 추출. 두 모드 모두 005 문서의 근거 충실성 원칙을 반드시 적용하며, 설명 기반 모드에서 미명시된 세부사항은 005 §6에 따라 표준 기본값을 명시적으로 라벨링하거나 사용자에게 질문 |
| 2 | 클라우드 식별 | **코드 기반**: provider prefix 기반 자동 판별. **설명 기반**: 서비스 명칭 키워드(EKS/NAT Gateway 등=AWS, AKS/VNet 등=Azure, Nova/Neutron/Keystone/Octavia 등=OpenStack)로 판별하고 모호하면 질문 |
| 3 | 리소스 그래프 추출 | 계층 매핑: Cloud > Region > VPC/VNet(OpenStack은 Neutron Network) > Subnet > Resource |
| 4 | drawio XML 생성 | 클라우드별 아이콘 스타일(020/030/035/040) + 공통 XML 규격(010) 적용. 좌표는 손으로 하드코딩하지 말고 `~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py`의 `grid`/`hstack`/`vstack`으로 계산(015). 읽는 사람 가독성을 위해 `title()`(제목/범위)·`legend()`(색·선 범례)를 포함하고 아이콘 라벨 줄바꿈·타이포그래피 위계를 적용(050) |
| 5 | 규칙 준수 검증 | 010 문서 2~9절(크기/헤더높이/라벨링/엣지/AZ 서브라벨/아이콘) + 015 문서(레이아웃 계산), 050 문서(범례/제목/라벨/타이포그래피), 005 문서(근거 충실성) 체크리스트 대조 검증. `layout_toolkit.validate()`로 겹침까지 기계적 확인 후 렌더링 결과를 육안으로도 확인 |

## 3. 작업 프로세스 제약 (Operational Gate)

- **[NEVER] 폴더/모듈 구조 다이어그램 금지 (Anti-Pattern)**: 사용자 요청에 "폴더", "구조", "리포지토리" 등의 표현이 포함되어 있어도, 이 스킬의 산출물은 항상 2절 프로세스 표의 계층(Cloud > Region > VPC/VNet > Subnet > Resource)을 따르는 실제 네트워크/인프라 토폴로지여야 합니다. Terraform 디렉토리·모듈·파일 트리 자체를 노드로 그리는 "코드 구조 다이어그램"(예: `modules/`, `main.tf` 등을 박스로 나열)은 이 스킬의 산출물이 아니므로 생성하지 마십시오.
- **[PREFER] 기존 참고 산출물 우선 확인**: 작업 대상과 동일한 인프라를 다루는 `.drawio` 파일이 워크스페이스에 이미 존재하면, XML 생성 전에 반드시 열어 확인하십시오. 존재할 경우 그 다이어그램의 유형(계층 구조, 아이콘 매핑, 라벨링 컨벤션)을 최우선 템플릿으로 삼아 일관성을 유지하고, 이유 없이 다른 유형으로 임의 전환하지 마십시오.
- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: XML을 생성하기 전, 반드시 1절 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서, 예: 010이 가리키는 `000-core.md`)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집하십시오.
- **[MUST] 클라우드 식별**: 코드 기반 모드에서는 IaC 코드의 provider prefix로 대상 클라우드를 판별하십시오. (`aws_` = AWS, `azurerm_` = Azure, `openstack_` = OpenStack, CloudFormation = AWS, Bicep/ARM = Azure, Heat HOT `type: OS::*` = OpenStack) 설명 기반 모드에서는 사용자 발화에 등장하는 서비스 명칭으로 판별하십시오. (EKS/NAT Gateway/ALB/S3 등 = AWS, AKS/VNet/App Service 등 = Azure, Nova/Neutron/Cinder/Swift/Keystone/Octavia/Magnum/Ironic/Trove/Heat 등 = OpenStack) 두 클라우드 서비스가 함께 언급되면 하이브리드 구성으로 판단하고 `multi-cloud` 스킬 룰북을 함께 참조하십시오.
- **[MUST] 설명 기반 모드의 근거 충실성**: 코드 없이 자연어 설명만으로 다이어그램을 생성할 때는 005-fidelity-anti-hallucination-standard.md §6의 규칙(명시된 요소만 반영, 미명시 세부사항은 표준 기본값 + 명시적 라벨링, 중대한 모호성은 질문)을 반드시 적용하십시오.
- **[MUST] 라벨링/컨벤션은 010 문서의 명시 규칙을 그대로 적용**: 서브넷 용도 설명(CIDR 필수 포함), 엣지 라벨 부여 기준, 다중 AZ 분산 서브라벨, 서드파티 도구 아이콘 표현, 컨테이너 헤더 높이·아이콘 기본 크기, 레이아웃 계산 원칙은 010-drawio-xml-standard.md 2~10절에 이미 규칙과 예시 문자열로 고정되어 있습니다. "이 정도 품질"을 스스로 해석하지 말고, 해당 규칙을 그대로 기계적으로 적용하십시오. 실행마다 결과가 달라지는 것을 방지하기 위한 것이므로 임의 재해석을 금지합니다.
- **[MUST] 아이콘 라이브러리 참조**: 대상 클라우드에 맞는 아이콘 스타일 라이브러리(AWS=020, Azure=030, OpenStack=035, 서드파티는 040)를 읽고 정확한 style 속성을 적용하십시오. OpenStack은 테넌트 리소스 17종(`openstack_native_icon()`)에 한해 draw.io 내장 스텐실이 존재하고, 그 외 컨트롤 플레인 서비스는 035의 함수형 블록(`openstack_icon()`, 공식 색상 표준에 따라 기본 검정+절제된 강조) 규칙을 반드시 따르며 존재하지 않는 shape/로고 URL을 창작하지 마십시오.
- **[MUST] 가독성 요소 필수 포함(범례/제목)**: 배치가 안 겹치는 것만으로는 "읽기 쉬운" 다이어그램이 아닙니다. 050-readability-standard.md에 따라 다이어그램에 등장한 색·선 종류를 설명하는 범례(`layout_toolkit.legend()`)와 대상·범위를 알리는 제목 블록(`layout_toolkit.title()`)을 반드시 포함하고, 아이콘 라벨 자동 줄바꿈과 타이포그래피 위계(제목20/헤더13/라벨12/서브라벨10)를 적용하십시오. 색·선 종류가 2가지 이상인데 범례가 없으면 완료로 간주하지 마십시오.
- **[MUST] 좌표는 공용 툴킷으로 계산**: 서브넷/컨테이너/아이콘 좌표를 손으로 하나씩 대입하지 말고 `~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py`를 import해서 `grid`/`hstack`/`vstack`/`offset_by_header`/`subnet_box_size`로 계산하십시오(015). 헤더 높이 오프셋 누락, 형제 컨테이너 높이 불일치, 콘텐츠 대비 과도한 여백은 전부 이 툴킷을 안 쓰고 좌표를 즉흥적으로 정할 때 발생한 실제 재발 버그입니다.
- **[MUST] 사후 통합 검증**: XML 생성 직후, 작업을 완료 선언하기 전에 `python3 ~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py {파일경로}`로 ID 중복/끊어진 참조/형제 겹침/행 높이 불일치/라벨 폭 초과를 기계적으로 검증하십시오(090-validation-standard.md §2~3). CLI 실행 시 `{파일명}-preview.png`(엣지 포함 렌더링)가 자동 생성되므로, 이를 직접 열어 박스 정렬과 엣지 라우팅이 다른 서브넷을 뚫고 지나가지 않는지 육안으로도 확인한 뒤에만 완료를 선언하십시오. 서드파티 아이콘 URL은 네트워크가 가능하면 `check_icon_urls()`로 추가 확인하십시오.
- **[MUST] 최종 산출물은 실제 `.drawio` 파일로 저장**: 생성한 XML은 화면 미리보기로만 제시하지 말고, 반드시 확장자 `.drawio`인 실제 파일로 저장하십시오. 기본 저장 위치는 다이어그램이 다루는 대상 프로젝트의 저장소 루트(예: `his-infra` 아키텍처 요청 시 `his-infra/<파일명>.drawio`)이며, 파일명은 대상과 범위를 알 수 있는 kebab-case(예: `his-infra-architecture-aws-main.drawio`)로 지정하십시오. 코드 없이 순수 설명 기반 요청 등 대상 프로젝트 저장소가 불분명한 경우에만 저장 위치를 사용자에게 확인하십시오.
- **[MUST] HTML 시각 미리보기 아티팩트는 기본 생성 금지**: 사용자가 "미리보기도 보여줘", "화면에서 보고 싶다"처럼 명시적으로 요청하지 않는 한, `.drawio` 파일과 별도로 HTML/SVG 기반 시각화 아티팩트를 추가로 만들지 마십시오. 완료 보고 시에는 저장된 `.drawio` 파일의 절대 경로와 diagrams.net(app.diagrams.net)에서 여는 방법만 안내하십시오.
