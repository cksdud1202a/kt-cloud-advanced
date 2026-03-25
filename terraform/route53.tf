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
# cloudflare_tunnel_domain 준비되면 주석 해제
# resource "aws_route53_health_check" "onprem" {
#   fqdn              = var.cloudflare_tunnel_domain
#   port              = 80
#   type              = "HTTP"
#   resource_path     = "/"
#   failure_threshold = 3
#   request_interval  = 10
#
#   tags = {
#     Name    = "${var.project_name}-onprem-hc"
#     Project = var.project_name
#   }
# }


#######################################
# Route 53 Failover Records
#######################################

# cloudflare_tunnel_domain 준비되면 주석 해제
# resource "aws_route53_record" "primary" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "www.${var.domain_name}"
#   type    = "CNAME"
#   ttl     = 60
#
#   failover_routing_policy {
#     type = "PRIMARY"
#   }
#
#   records         = [var.cloudflare_tunnel_domain]
#   health_check_id = aws_route53_health_check.onprem.id
#   set_identifier  = "primary"
# }

# Secondary 레코드 (AWS ALB - 장애 시 트래픽)
# health_check_id 제거 → Primary 장애 시 무조건 ALB로 Failover (last resort)
# health check를 붙이면 ALB도 unhealthy일 때 아무 레코드도 서빙 안 하는 문제 발생
#
# var.alb_dns가 비어있으면(LBC 배포 전) 레코드 생성 안 함.
# LBC + Ingress 배포 후 ALB DNS를 확인하고 아래처럼 apply:
#   terraform apply -var="alb_dns=hybrid-dr-alb-xxxx.ap-northeast-2.elb.amazonaws.com"
resource "aws_route53_record" "secondary" {
  count = var.alb_dns != "" ? 1 : 0

  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  failover_routing_policy {
    type = "SECONDARY"
  }

  records        = [var.alb_dns]
  set_identifier = "secondary"
}