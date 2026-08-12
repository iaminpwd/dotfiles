#!/usr/bin/env bash
set -euo pipefail

# 히어독 본문은 실행되는 코드가 아니므로 멱등성 검사 대상이 아니다.
# 대시 형식, 따옴표 감싼 구분자, 일반 형식 세 가지를 모두 담는다.
cat <<-EOF
	echo "sample" >> /tmp/example.log
	EOF

cat <<"EOF"
echo "sample" >> /tmp/example.log
EOF

cat <<EOF
echo "sample" >> /tmp/example.log
EOF
