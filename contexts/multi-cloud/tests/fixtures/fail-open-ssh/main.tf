# 010-multi-cloud-core.md 4절 중단 조건 재현: "클라우드 이기종 간의 통신이 VPN IPsec 또는
# ExpressRoute/Direct Connect 전용선 경로를 타지 않고, 일반 Public IP 엔드포인트에
# 0.0.0.0/0 노출 상태로 직접 연동을 시도하는 IaC 구성이 감지될 시 즉시 작업을 중단(Hard Block)".
# 이 조항이 사람 눈이 아니라 checkov CKV_AWS_24 로 실제 차단되는지 고정한다.
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

resource "aws_security_group" "open_gateway" {
  name_prefix = "sample-dev-gateway-"
  description = "intentionally exposed hybrid gateway (VPN 터널을 우회한 위반 재현)"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from anywhere (전용선/터널 경로 우회)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "vpc_id" {
  type        = string
  description = "대상 VPC 식별자"
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
