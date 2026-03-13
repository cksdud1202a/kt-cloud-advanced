# Worker Node SG (EKS Node Group)
resource "aws_security_group" "worker_node" {
  name   = "${var.project_name}-worker-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "EKS Control Plane to Worker Node"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH via Tailscale only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]  # Tailscale IP 대역
  }

  ingress {
    description = "Kubelet EKS Control Plane to Worker Nod"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]  # VPC 내부
  }

  ingress {
    description = "NodePort range ALB to Worker Node"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }

  ingress {
    description = "Tailscale UDP"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Worker Node 간 통신 (Pod 간 통신, CNI)
  ingress {
    description = "Worker Node internal communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true  # 같은 SG끼리 허용
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-worker-sg" }
}

# Monitoring EC2 SG (Prometheus + Grafana + Tailscale)
resource "aws_security_group" "monitoring" {
  name   = "${var.project_name}-monitoring-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Grafana via Tailscale"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]
  }

  ingress {
    description = "Prometheus via Tailscale"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]
  }

  ingress {
    description = "SSH via Tailscale"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]
  }

  ingress {
    description = "Tailscale UDP"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-monitoring-sg" }
}

# DR RDS SG
resource "aws_security_group" "rds" {
  name   = "${var.project_name}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "MySQL from VPC (Worker Node, DMS)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }

  ingress {
    description = "MySQL from Tailscale (on-premises DMS)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}

# ALB SG (장애 시 Failover용)
resource "aws_security_group" "alb" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}