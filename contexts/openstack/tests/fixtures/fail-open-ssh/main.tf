# 050-iac-standard.md 4절 중단 조건 재현: "SSH(22포트) 등 민감 포트가 0.0.0.0/0 으로
# 과도하게 개방되는 보안 규칙이 감지되면 즉시 작업을 멈추고 보안 위반을 보고(Hard Block)".
# 이 조항이 사람 눈이 아니라 checkov CKV_OPENSTACK_2 로 실제 차단되는지 고정한다.
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
  description       = "SSH from anywhere"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

variable "os_cloud" {
  type        = string
  description = "clouds.yaml 에 정의된 클라우드 프로파일 이름"
}
