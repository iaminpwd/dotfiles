task-id: 20260728_000000

# 픽스처: 검증 블록이 실패하는 설계도

## 1. Goal
지시가 반영되지 않았을 때 검증 블록이 실제로 비영(非零) 종료 코드를 내는지 확인한다.

## 4. Verification
```bash
test -f absent-marker.txt
```
