# ----------------------------------------
# security.tf
# ----------------------------------------

# EKS Control Plane Security Group
resource "aws_security_group" "eks_cluster" {
  name   = "${var.project_name}-eks-cluster-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-eks-cluster-sg" }
}

# Worker Node Security Group
resource "aws_security_group" "worker_node" {
  name   = "${var.project_name}-worker-sg"
  vpc_id = aws_vpc.main.id

  # ingress 블록 전부 제거
  # 아래 aws_security_group_rule로 관리

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = [ingress]
  }

  tags = { Name = "${var.project_name}-worker-sg" }
}

# SSH via Tailscale
resource "aws_security_group_rule" "worker_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["100.64.0.0/10"]
  security_group_id = aws_security_group.worker_node.id
  description       = "SSH via Tailscale only"
}

# Tailscale UDP
resource "aws_security_group_rule" "worker_tailscale_udp" {
  type              = "ingress"
  from_port         = 41641
  to_port           = 41641
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker_node.id
  description       = "Tailscale UDP"
}

# Worker Node 간 내부 통신
resource "aws_security_group_rule" "worker_internal" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.worker_node.id
  description       = "Worker Node internal communication"
}

# [변경] ingress 블록에서 source_security_group_id 못 써서
# aws_security_group_rule로 분리

# 443: Control Plane → Worker Node
resource "aws_security_group_rule" "worker_from_eks_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.worker_node.id
  description              = "EKS Control Plane to Worker Node 443"
}

resource "aws_security_group_rule" "eks_from_worker_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker_node.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "Worker Node to Control Plane 443"
}

# 10250: Control Plane → Worker Node Kubelet
resource "aws_security_group_rule" "worker_from_eks_10250" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.worker_node.id
  description              = "Kubelet EKS Control Plane to Worker Node"
}

# 30000~32767: ALB → Worker Node NodePort
resource "aws_security_group_rule" "worker_from_alb_nodeport" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.worker_node.id
  description              = "NodePort range ALB to Worker Node"
}

# Monitoring EC2 Security Group
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
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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


# DR RDS Security Group
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

# DMS Security Group
# DMS 전용 SG — RDS SG와 분리하여 역할 명확화
# DMS는 인바운드 필요 없음 (DMS가 먼저 연결 시도)
# 아웃바운드: 온프레미스 MySQL(Tailscale) + DR RDS(VPC 내부) 접근
resource "aws_security_group" "dms" {
  name   = "${var.project_name}-dms-sg"
  vpc_id = aws_vpc.main.id

  egress {
    description = "DMS to on-premises MySQL via Tailscale"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]
  }

  egress {
    description = "DMS to DR RDS via VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }

  tags = { Name = "${var.project_name}-dms-sg" }
}

# ALB Security Group
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}