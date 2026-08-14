# 방향이 type 인자로 갈리는 구형 aws_security_group_rule 의 egress 쪽. DB 포트로 나가는
# egress 를 0.0.0.0/0 으로 여는 것은 정상 구성이므로 통과해야 한다.
#
# 이 픽스처가 없던 동안 검사기의 is_egress 판정 경로 전체가 미검증이었다. fail-sg-rule-ingress
# 주석은 "ok-egress-open 과 짝"이라고 했지만 그쪽은 인라인 egress 블록이라 애초에 블록
# 진입 조건(ingress 계열)에 걸리지 않아 is_egress 를 타지 않는다 — 즉 짝이 실제로는
# 없었고, is_egress 를 0 으로 못박아도 스위트가 그대로 통과했다(뮤테이션으로 확인).
resource "aws_security_group_rule" "db_egress_open" {
  type              = "egress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}
