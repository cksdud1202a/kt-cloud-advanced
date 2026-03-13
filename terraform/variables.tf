variable "region" {
  default = "ap-northeast-2"
}

variable "project_name" {
  default = "hybrid-dr"
}

variable "worker_instance_type" {
  default = "t3.small"
}

variable "monitoring_instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  default = "my-terraform-key"  # 실제 보유한 키페어 이름
}

variable "db_password" {
  description = "RDS master password"
  sensitive   = true  # terraform plan/apply 출력에서 값 숨김
}

variable "onprem_mysql_ip" {
  description = "온프레미스 MySQL Tailscale IP"
}

variable "domain_name" {
  description = "테스트용 도메인 이름"
  default     = "test.hybrid-dr.com"
}

variable "cloudflare_tunnel_domain" {
  description = "온프레미스 Cloudflare Tunnel 도메인"
}