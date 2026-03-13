########################################
# ALB (Application Load Balancer)
# 장애 시 Route 53 Failover로 트래픽 전환될 때 사용
########################################

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false  # 외부 인터넷에서 접근 가능
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id]

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

########################################
# ALB Target Group
########################################

# ALB가 트래픽을 보낼 Worker Node 대상 그룹
resource "aws_lb_target_group" "main" {
  name     = "${var.project_name}-tg"
  port     = 30080  # NGINX NodePort
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Worker Node 헬스체크
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "30080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
  }

  tags = {
    Name    = "${var.project_name}-tg"
    Project = var.project_name
  }
}

########################################
# ALB Listener
########################################

# 80 포트로 들어오는 트래픽을 Target Group으로 전달
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}