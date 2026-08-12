#!/usr/bin/env bash
set -euo pipefail

# 히어독이 끝난 뒤의 진짜 append 는 여전히 잡혀야 한다
# (히어독 상태에서 빠져나오지 못하면 이하 전부가 조용히 미검사된다).
cat <<-EOF
	echo "in heredoc" >> /tmp/example.log
	EOF

echo "real unguarded" >> /tmp/example.log
