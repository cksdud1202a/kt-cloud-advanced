########################################
# Provider
########################################

# Terraform이 AWS를 사용하겠다고 선언
# version ~> 5.0 은 5.x 버전대 사용한다는 의미
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS 리전 설정
# var.region은 variables.tf에서 정의한 변수
provider "aws" {
  region = var.region
}

########################################
# Data Sources
########################################

# 가장 최신 Ubuntu 22.04 AMI를 자동으로 찾아옴
# 직접 AMI ID 하드코딩하면 리전마다 달라서 이렇게 자동 검색
data "aws_ami" "ubuntu" {
  most_recent = true  # 가장 최신 버전 선택
  filter {
    name   = "name"
    # ubuntu 공식 22.04 amd64 이미지 패턴으로 검색
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  # 099720109477 = Canonical(Ubuntu 만드는 회사) 공식 계정 ID
  owners = ["099720109477"]
}


########################################
# EKS Cluster
########################################

resource "aws_eks_cluster" "main" {
  # EKS 클러스터 이름 (예: hybrid-dr-eks)
  name = "${var.project_name}-eks"

  # EKS가 AWS 리소스 관리할 때 사용할 IAM Role
  # iam.tf에서 정의한 eks_cluster role 참조
  role_arn = aws_iam_role.eks_cluster.arn

  # K8s 버전
  version = "1.29"

  vpc_config {
    # EKS Worker Node가 있는 서브넷
    # public + private 두 AZ에 걸쳐야 EKS 생성 가능
    subnet_ids = [
    aws_subnet.public.id,
    aws_subnet.private.id
    ]
    
    # EKS Control Plane이 사용할 Security Group
    security_group_ids = [aws_security_group.worker_node.id]

    # 외부(인터넷)에서 EKS API Server 접근 허용
    # kubectl로 외부에서 접근할 때 필요
    endpoint_public_access = true

    # VPC 내부에서도 EKS API Server 접근 허용
    # Worker Node가 Control Plane과 통신할 때 사용
    endpoint_private_access = true
  }

  # IAM Role 정책 연결이 완료된 후에 EKS 클러스터 생성
  # 순서 보장을 위해 depends_on 사용
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource,
  ]

  tags = {
    Name    = "${var.project_name}-eks"
    Project = var.project_name
  }
}

########################################
# EKS Node Group (Worker Node)
########################################

# Worker Node EC2에 Name 태그 붙이기 위한 Launch Template
resource "aws_launch_template" "worker" {
  name = "${var.project_name}-worker-lt"

  # EC2 인스턴스에 붙일 태그 설정
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-worker-node"
      Project = var.project_name
    }
  }
}

resource "aws_eks_node_group" "worker" {
  # 어느 EKS 클러스터에 붙을지
  cluster_name = aws_eks_cluster.main.name

  # Node Group 이름
  node_group_name = "${var.project_name}-worker"

  # Worker Node EC2가 사용할 IAM Role
  node_role_arn = aws_iam_role.eks_node.arn

  # Worker Node가 생성될 서브넷
  subnet_ids = [aws_subnet.public.id]

  # EC2 인스턴스 타입 (variables.tf에서 정의)
  instance_types = [var.worker_instance_type]

  # Launch Template 연결 (Name 태그 적용)
  launch_template {
    id      = aws_launch_template.worker.id
    version = aws_launch_template.worker.latest_version
  }
  
  scaling_config {
    # 평시 Warm Standby: 1개만 유지
    desired_size = 1
    # 최소 1개는 항상 켜져 있어야 함
    min_size = 1
    # 장애 시 Karpenter가 최대 5개까지 늘릴 수 있음
    max_size = 5
  }

  update_config {
    # 업데이트 시 한 번에 최대 1개 노드만 중단
    max_unavailable = 1
  }

  # K8s에서 이 노드를 식별하는 라벨
  labels = {
    role = "worker"
  }

  # IAM 정책 연결 완료 후 Node Group 생성
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr,
  ]

  tags = {
    Name    = "${var.project_name}-worker"
    Project = var.project_name
    # Karpenter가 이 태그로 노드 검색해서 관리
    "karpenter.sh/discovery" = var.project_name
    # 이 노드가 해당 EKS 클러스터 소속임을 표시
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

########################################
# Monitoring EC2
########################################

resource "aws_instance" "monitoring" {
  # 위에서 검색한 최신 Ubuntu AMI 사용
  ami = data.aws_ami.ubuntu.id

  # EC2 인스턴스 타입 (variables.tf에서 정의)
  instance_type = var.monitoring_instance_type

  # Public Subnet에 배치 (Tailscale로 접근)
  subnet_id = aws_subnet.public.id

  # SSH 접근용 Key Pair 이름
  key_name = var.key_name

  # Monitoring EC2 전용 Security Group 적용
  vpc_security_group_ids = [aws_security_group.monitoring.id]

  # EC2에 붙일 IAM Instance Profile
  # CloudWatch 등 AWS 서비스 접근 권한
  iam_instance_profile = aws_iam_instance_profile.monitoring.name

  # EC2 처음 시작할 때 자동으로 실행되는 스크립트
  user_data = <<-EOF
    #!/bin/bash

    # Swap 메모리 2GB 설정
    # 메모리 부족할 때 디스크를 임시 메모리로 사용
    fallocate -l 2G /swapfile
    chmod 600 /swapfile      # 보안을 위해 root만 접근 가능하게
    mkswap /swapfile         # swap 파일 포맷
    swapon /swapfile         # swap 활성화
    # 재부팅 후에도 swap 유지되도록 fstab에 등록
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # 패키지 목록 업데이트
    apt-get update -y

    # Tailscale 설치 (온프레미스 ↔ AWS VPN 연결용)
    curl -fsSL https://tailscale.com/install.sh | sh

    # Docker 설치 (Prometheus, Grafana 컨테이너 실행용)
    apt-get install -y docker.io
    systemctl enable docker   # 부팅 시 자동 시작
    systemctl start docker    # 즉시 시작

    # Prometheus 컨테이너 실행
    # 9090 포트로 메트릭 수집
    # --restart always: EC2 재시작해도 자동으로 컨테이너 재시작
    docker run -d \
      --name prometheus \
      --restart always \
      -p 9090:9090 \
      prom/prometheus

    # Grafana 컨테이너 실행
    # 3000 포트로 대시보드 접근
    docker run -d \
      --name grafana \
      --restart always \
      -p 3000:3000 \
      grafana/grafana
  EOF

  tags = {
    Name    = "${var.project_name}-monitoring"
    Project = var.project_name
    Role    = "monitoring"
  }
}

# Monitoring EC2에 IAM Role 연결하기 위한 Instance Profile
# EC2는 Role을 직접 연결 못하고 Instance Profile을 통해 연결
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-monitoring-profile"
  # iam.tf에서 정의한 monitoring role 참조
  role = aws_iam_role.monitoring.name
}