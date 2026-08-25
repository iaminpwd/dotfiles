#!/usr/bin/env bash
# 위 fail-heredoc-append.sh 의 짝. 같은 한 줄 형태라도 상태 확인 가드가 함께 있으면
# 경고가 뜨면 안 된다. 이 짝이 없으면 "히어독 시작 줄을 무조건 위반으로 신고"하는
# 반대 방향 퇴화(정상 멱등 코드까지 경고)를 아무도 잡지 못한다.
set -euo pipefail

echo "unrelated line 1"
echo "unrelated line 2"
echo "unrelated line 3"
echo "unrelated line 4"
grep -q "export SAMPLE_VAR=1" /tmp/output.log 2>/dev/null || cat >>/tmp/output.log <<'EOF'
export SAMPLE_VAR=1
EOF
echo "unrelated line 5"
echo "unrelated line 6"
echo "unrelated line 7"
echo "unrelated line 8"
