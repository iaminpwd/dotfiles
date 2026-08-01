# 010-multi-cloud-core.md 3절 검증 게이트 재현: pre-flight-check.sh 는 terraform fmt
# -check 를 통과하지 못하면 커밋을 차단한다. 들여쓰기만 어긋뜨린 변형이다.
terraform {
      required_version = "~> 1.5"
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
