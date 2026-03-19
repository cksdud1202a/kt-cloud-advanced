# ----------------------------------------
# variables.tf
# 이 파일은 프로젝트 전체에서 공통으로 쓰는 변수를 정의함
# 다른 .tf 파일에서 var.xxx 형태로 가져다 씀
# ----------------------------------------

# AWS 리전 설정
# ap-northeast-2 = 서울 리전
variable "region" {
  default = "ap-northeast-2"
}

# 프로젝트 이름
# 예: hybrid-dr-eks, hybrid-dr-alb, hybrid-dr-vpc
variable "project_name" {
  default = "hybrid-dr"
}

# Worker Node EC2 인스턴스 타입
# Warm Standby라 평시엔 최소 스펙 유지
variable "worker_instance_type" {
  default = "t3.small"
}

# Monitoring EC2 인스턴스 타입
variable "monitoring_instance_type" {
  default = "t3.micro"
}

# EC2 SSH 접속용 키페어 이름
# AWS 콘솔에서 미리 만들어둔 키페어 이름 입력
variable "key_name" {
  default = "my-terraform-key"  # 실제 보유한 키페어 이름
}

# RDS 마스터 비밀번호
# sensitive = true → terraform plan/apply 출력에서 값이 ***로 가려짐
# 실행 시 직접 입력하거나 terraform.tfvars에 저장
variable "db_password" {
  description = "RDS master password"
  sensitive   = true  # terraform plan/apply 출력에서 값 숨김
}

# 온프레미스 MySQL 복제 전용 계정 비밀번호 (repl_user)
variable "onprem_repl_password" {
  description = "온프레미스 MySQL 복제 전용 계정(repl_user) 비밀번호"
  sensitive   = true
}

# 온프레미스 MySQL 접속 IP
# Tailscale VPN으로 연결된 온프레미스 서버의 IP
# DMS가 이 IP로 소스 MySQL에 접속해서 CDC 복제함
variable "onprem_mysql_ip" {
  description = "온프레미스 MySQL Tailscale IP"
}

# Route53에 등록할 도메인 이름
# Primary(온프레미스), Secondary(ALB) 레코드 둘 다 이 도메인 사용
variable "domain_name" {
  description = "테스트용 도메인 이름"
  default     = "test.hybrid-dr.com"
}

# 온프레미스 Cloudflare Tunnel 도메인
# Route53 Primary 레코드가 이 도메인으로 트래픽 보냄
# 온프레미스가 살아있을 때 여기로 연결됨
variable "cloudflare_tunnel_domain" {
  description = "온프레미스 Cloudflare Tunnel 도메인"
}