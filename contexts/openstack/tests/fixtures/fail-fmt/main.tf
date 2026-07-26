# 050-iac-standard.md 3절 검증 게이트 재현: pre-flight-check.sh 는 terraform fmt
# -check 를 통과하지 못하면 커밋을 차단한다. 들여쓰기만 어긋뜨린 변형이다.
terraform {
      required_version = "~> 1.5"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

# 자격 증명은 코드에 넣지 않고 clouds.yaml / OS_* 환경 변수로 주입한다
provider "openstack" {
  cloud = var.os_cloud
}

resource "openstack_networking_secgroup_v2" "app" {
  name        = "sample-dev-app-secgroup"
  description = "sample app security group"
}

resource "openstack_networking_secgroup_rule_v2" "https_from_vpn" {
  security_group_id = openstack_networking_secgroup_v2.app.id
  description       = "HTTPS from corporate VPN"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.vpn_cidr
}

variable "os_cloud" {
  type        = string
  description = "clouds.yaml 에 정의된 클라우드 프로파일 이름"
}

variable "vpn_cidr" {
  type        = string
  description = "사내 VPN CIDR 대역"
}
