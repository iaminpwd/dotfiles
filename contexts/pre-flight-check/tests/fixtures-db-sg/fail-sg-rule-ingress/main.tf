# 방향이 type 인자로 갈리는 구형 aws_security_group_rule. type = "egress" 인 같은
# 형태는 통과해야 하므로(ok-sg-rule-egress 와 짝), 여기서는 ingress 만 차단되는지 본다.
# (예전 주석은 ok-egress-open 을 짝으로 지목했지만 그쪽은 인라인 egress 블록이라 이
#  리소스 타입의 판정 경로를 전혀 타지 않는다 — 실제 짝은 ok-sg-rule-egress 다.)
resource "aws_security_group_rule" "db_open" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}
