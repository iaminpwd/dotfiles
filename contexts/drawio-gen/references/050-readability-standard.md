---
trigger: drawio XML 생성 시 가독성(범례/제목/라벨/타이포그래피) 계약을 확인할 때 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
  - contexts/drawio-gen/references/090-validation-standard.md
---
# 다이어그램 가독성 계약

레이아웃 계산은 015, XML/팔레트는 010, 완료 검증은 090을 따른다. 이 문서에는 독자가 실제 산출물에서 확인해야 하는 가독성 계약만 둔다.

## 1. 범례

- **[MUST]** 다이어그램에 실제 사용한 컨테이너 색과 실선/점선의 의미를 범례로 설명한다. 사용하지 않은 요소를 범례에 추가하지 않는다.
- **[MUST]** `layout_toolkit.py`의 `legend(id, x, y, entries)`를 사용한다. `entries`는 `("box"|"line"|"dash", color, label)` 형식이다.
- **[MUST]** 범례는 컨테이너와 겹치지 않는 여백에 배치한다. 범례 테두리는 `#666666`을 사용한다.
- `validate()`가 `[WARN] 범례 누락 의심`을 내면 완료 전에 범례를 추가하거나 실제로 경고가 예외인 이유를 확인한다.

## 2. 제목과 범위

- **[MUST]** 캔버스 좌상단에 `title(id, title, x, y, subtitle=...)`로 대상 시스템과 범위를 표시한다.
- 부제에는 클라우드·리전·구성 티어 등 근거 있는 범위를 넣는다. 추정한 값은 SKILL.md의 근거 계약에 따라 `(가정: ...)`으로 표시한다.

## 3. 라벨

- **[MUST]** 아이콘은 `aws_icon()`, `azure_icon()`, `openstack_icon()`, `thirdparty_icon()`, `gitlab_icon()` 헬퍼를 사용해 `whiteSpace=wrap` 계약을 유지한다.
- 서브라벨은 짧게 유지하고 의도한 줄바꿈은 `<br>`로 표시한다. `validate()`의 `[WARN] 라벨 폭 초과 의심`이 나오면 문장을 줄이거나 줄바꿈한다.

## 4. 타이포그래피

- **[MUST]** 툴킷의 `FONT_TITLE=20`, `FONT_HEADER=13`, `FONT_LABEL=12`, `FONT_SUBLABEL=10` 위계를 유지한다.
- 강조는 임의의 새 폰트 크기보다 `fontStyle=1` 또는 색상으로 표현한다.

## 5. 검증

완료 조건과 XML/ID/참조/겹침/팔레트/라벨/범례/preview 검증은 `090-validation-standard.md`를 단일 기준으로 사용한다.
