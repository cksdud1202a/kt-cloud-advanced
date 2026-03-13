########################################
# Route 53 Hosted Zone
########################################

# 테스트용 임시 도메인
resource "aws_route53_zone" "main" {
  name = var.domain_name  # variables.tf에서 정의

  tags = {
    Name    = "${var.project_name}-zone"
    Project = var.project_name
  }
}

########################################
# Route 53 Health Check (온프레미스)
########################################

# 온프레미스 Cloudflare Tunnel 엔드포인트 헬스체크
resource "aws_route53_health_check" "onprem" {
  fqdn              = var.cloudflare_tunnel_domain  # 온프레미스 도메인
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3   # 3번 실패하면 장애로 판단
  request_interval  = 10  # 10초마다 체크

  tags = {
    Name    = "${var.project_name}-onprem-hc"
    Project = var.project_name
  }
}

########################################
# Route 53 Health Check (AWS ALB)
########################################

# AWS ALB 헬스체크
resource "aws_route53_health_check" "aws" {
  fqdn              = aws_lb.main.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 10

  tags = {
    Name    = "${var.project_name}-aws-hc"
    Project = var.project_name
  }
}

########################################
# Route 53 Failover Records
########################################

# Primary 레코드 (온프레미스 - 평시 트래픽)
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 60

  # Failover 라우팅 정책
  failover_routing_policy {
    type = "PRIMARY"
  }

  # 온프레미스 Cloudflare Tunnel 도메인
  records = [var.cloudflare_tunnel_domain]

  # 온프레미스 헬스체크 연결
  health_check_id = aws_route53_health_check.onprem.id
  set_identifier  = "primary"
}

# Secondary 레코드 (AWS ALB - 장애 시 트래픽)
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 60

  failover_routing_policy {
    type = "SECONDARY"
  }

  # AWS ALB DNS
  records = [aws_lb.main.dns_name]

  health_check_id = aws_route53_health_check.aws.id
  set_identifier  = "secondary"
}