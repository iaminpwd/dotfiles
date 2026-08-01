# 010-multi-cloud-core.md 는 aws/azure 코어 룰을 교차 참조하며, 그 코어 룰(050-iac-standard.md)의
# Version Pinning 조항("required_version, required_providers 는 특정 버전으로 고정")이
# 멀티 클라우드 IaC 에도 그대로 적용되는지 재현한다. required_version 을 제거한 변형이며,
# tflint terraform_required_version 이 잡아야 한다.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Project     = "sample"
      Environment = "dev"
      CostCenter  = "cc-1000"
    }
  }
}

resource "aws_security_group" "hybrid_interconnect" {
  name_prefix = "sample-dev-vpn-"
  description = "AWS-Azure 하이브리드 연동 구간 보안 그룹"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ipsec_from_onprem" {
  security_group_id = aws_security_group.hybrid_interconnect.id
  description       = "Azure VPN Gateway 측 전용선/터널 CIDR에서만 IPsec 허용"
  cidr_ipv4         = var.peer_tunnel_cidr
  from_port         = 500
  to_port           = 500
  ip_protocol       = "udp"
}

variable "vpc_id" {
  type        = string
  description = "대상 VPC 식별자"
}

variable "peer_tunnel_cidr" {
  type        = string
  description = "Azure 측 VPN Gateway 전용선 CIDR 대역"
}

resource "aws_network_interface" "gateway" {
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.hybrid_interconnect.id]
  description     = "hybrid interconnect gateway eni"
}

variable "subnet_id" {
  type        = string
  description = "대상 서브넷 식별자"
}
