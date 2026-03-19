########################################
# ALB (Application Load Balancer)
# 장애 시 Route 53 Failover로 트래픽 전환될 때 사용
########################################

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false  # 외부 인터넷에서 접근 가능
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public2.id]

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

# Target Group과 Listener는 AWS Load Balancer Controller가
# Ingress 리소스를 통해 자동으로 생성·관리함 (k8s/aws-lbc/ingress.yaml)