########################################
# EKS Cluster Role
########################################

# EKS Control Plane이 AWS 리소스 관리할 때 사용하는 Role
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  # EKS 서비스가 이 Role을 사용할 수 있도록 허용
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# EKS 클러스터 기본 권한 (노드 관리, 네트워크 설정 등)
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS가 VPC 리소스(ENI 등) 관리할 수 있도록 허용
resource "aws_iam_role_policy_attachment" "eks_vpc_resource" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

########################################
# EKS Node Role (Worker Node)
########################################

# Worker Node EC2가 EKS 클러스터에 조인할 때 사용하는 Role
resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  # EC2 서비스가 이 Role을 사용할 수 있도록 허용
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Worker Node가 EKS 클러스터에 조인하는 기본 권한
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Pod 네트워크(CNI) 관련 권한 (ENI 생성, IP 할당 등)
resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR에서 Docker 이미지 Pull 권한
resource "aws_iam_role_policy_attachment" "eks_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM으로 Worker Node에 접근 가능하게 (SSH 대체 수단)
resource "aws_iam_role_policy_attachment" "eks_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

########################################
# Karpenter Controller Role
########################################

# Karpenter가 EC2 노드를 자동으로 늘리고 줄일 때 사용하는 Role
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.project_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Karpenter가 EC2 노드 생성/삭제할 때 필요한 권한 (관리형 정책 없어서 직접 작성)
resource "aws_iam_role_policy" "karpenter_controller" {
  role = aws_iam_role.karpenter_controller.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",    # 노드 시작 템플릿 생성
          "ec2:CreateFleet",             # 여러 EC2 한번에 요청
          "ec2:RunInstances",            # EC2 실제 실행
          "ec2:CreateTags",             # 리소스 태그 붙이기
          "ec2:TerminateInstances",      # 불필요한 노드 삭제
          "ec2:DescribeInstances",       # 현재 인스턴스 목록 조회
          "ec2:DescribeInstanceTypes",   # 사용 가능한 인스턴스 타입 조회
          "ec2:DescribeSubnets",         # 서브넷 정보 조회
          "ec2:DescribeSecurityGroups",  # SG 정보 조회
          "ec2:DescribeImages",          # AMI 정보 조회
          "ec2:DescribeSpotPriceHistory",# 스팟 가격 조회
          "eks:DescribeNodegroup",       # 노드 그룹 정보 조회
          "iam:PassRole"                 # Worker Node Role을 EC2에 전달
        ]
        Resource = "*"
      }
    ]
  })
}

# Karpenter가 생성하는 노드에 적용되는 Role
resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

########################################
# DMS Role
########################################

# AWS DMS가 온프레미스 MySQL → DR RDS로 CDC 복제할 때 사용하는 Role
resource "aws_iam_role" "dms" {
  name = "${var.project_name}-dms-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })
}

# DMS가 VPC 내부 네트워크 리소스 관리하는 권한
resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS 작업 로그를 CloudWatch에 기록하는 권한
resource "aws_iam_role_policy_attachment" "dms_cloudwatch" {
  role       = aws_iam_role.dms.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

########################################
# Monitoring EC2 Role
########################################

# Monitoring EC2 (Prometheus + Grafana + Tailscale)가 사용하는 Role
resource "aws_iam_role" "monitoring" {
  name = "${var.project_name}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# CloudWatch에 메트릭/로그 전송 권한
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM으로 EC2 접근 권한 (SSH 없이 접근 가능)
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}