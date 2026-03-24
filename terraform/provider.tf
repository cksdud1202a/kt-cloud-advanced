# -----------------------------------------
# providers.tf
# Terraform 설정, AWS Provider, Data Sources 정의
# -----------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Tailscale 연결 후 활성화
    # mysql = {
    #   source  = "petoju/mysql"
    #   version = "~> 3.0"
    # }
  }
}

provider "aws" {
  region = var.region
}

# Tailscale 연결 후 활성화
# provider "mysql" {
#   endpoint = aws_db_instance.dr_rds.endpoint
#   username = "admin"
#   password = var.db_password
# }

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}