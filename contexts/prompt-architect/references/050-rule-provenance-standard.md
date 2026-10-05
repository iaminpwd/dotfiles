---
trigger: 이 저장소의 룰 조항을 추가·검토·삭제할 때 참조.
references:
  - contexts/prompt-architect/references/030-prompt-engineering-standard.md
---
# 룰의 유지와 검토

- 사용자 선호, 저장소 고유 경로·명령, 출력 계약, 반복 실패 방지책을 남긴다. 역할 선언과 일반 코딩 상식은 반복하지 않는다.
- 삭제 후보는 해당 문장이 없을 때 달라지는 행동과 근거를 확인한다. 효과가 불확실하면 대표 작업으로 비교하며, 짧아졌다는 이유만으로 성능 개선을 주장하지 않는다.
- 스크립트로 판정할 수 있는 조건은 검증기와 위반 픽스처로 확인한다. 새 검증 로직은 `contexts/drawio-gen/scripts/layout_toolkit.py`의 validate와 `contexts/drawio-gen/tests/run.sh`처럼 검증·픽스처·기대 결과를 연결한다.
- 조항의 필요성과 정책 변경은 사람이 검토한다. 참조·번호·라우팅 정합성과 프롬프트 린트는 `030-prompt-engineering-standard.md`를 따른다.
- 검증기 변경에는 해당 위반을 재현하는 픽스처를 포함하고 기존 회귀 검사를 실행한다.
