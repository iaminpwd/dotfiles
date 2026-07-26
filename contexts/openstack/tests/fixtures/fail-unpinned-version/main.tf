# 050-iac-standard.md 2.1 Version Pinning 재현: "Terraform 코어 및 Provider 버전
# (required_version, required_providers)은 특정 버전으로 고정". required_version 을
# 제거한 변형이며, tflint terraform_required_version 이 잡아야 한다.
terraform {
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
