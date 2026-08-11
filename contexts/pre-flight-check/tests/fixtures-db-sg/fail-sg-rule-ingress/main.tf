# 방향이 type 인자로 갈리는 구형 aws_security_group_rule. type = "egress" 인 같은
# 형태는 통과해야 하므로(ok-egress-open 과 짝), 여기서는 ingress 만 차단되는지 본다.
resource "aws_security_group_rule" "db_open" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}
