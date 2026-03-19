# ----------------------------------------
# eks.tf
# EKS 클러스터, Worker Node Group, Launch Template 정의
# ----------------------------------------

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  role_arn = aws_iam_role.eks_cluster.arn  # iam.tf 참조
  version  = "1.29"

  # 인증 모드
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    # public (Worker Node) 
    subnet_ids = [
      aws_subnet.public.id,  # AZ-a
      aws_subnet.public2.id, # AZ-b
    ]

    # security.tf에서 추가한 Control Plane 전용 SG
    security_group_ids = [aws_security_group.eks_cluster.id]

    # kubectl로 외부에서 EKS API 접근 허용
    endpoint_public_access  = true

    # VPC 내부에서도 EKS API 접근 허용
    # Worker Node → Control Plane 통신에 필요
    endpoint_private_access = true
  }

  # IAM Role 정책 연결 완료 후 EKS 클러스터 생성
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource,
  ]

  tags = {
    Name    = "${var.project_name}-eks"
    Project = var.project_name
  }
}

# ----------------------------------------
# Launch Template
# Worker Node EC2에 Name 태그 붙이기 위한 용도
# EKS Node Group 자체엔 Name 태그 설정이 없어서 우회
# ----------------------------------------

resource "aws_launch_template" "worker" {
  name = "${var.project_name}-worker-lt"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-worker-node"
      Project = var.project_name
    }
  }
}

# ----------------------------------------
# EKS Node Group (Worker Node)
# ----------------------------------------

resource "aws_eks_node_group" "worker" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-worker"
  node_role_arn   = aws_iam_role.eks_node.arn  # iam.tf 참조

  # Worker Node는 public1 (AZ-a), public2 (AZ-b)에 배치
  # Karpenter가 DR 시 두 AZ에 분산 배치 (고가용성)
  subnet_ids = [aws_subnet.public.id, aws_subnet.public2.id]

  instance_types = [var.worker_instance_type]  # t3.small

  launch_template {
    id      = aws_launch_template.worker.id
    version = aws_launch_template.worker.latest_version
  }

  scaling_config {
    # Warm Standby: 평시엔 1개만 유지 (비용 절감)
    desired_size = 1
    min_size     = 1
    # 장애 시 Karpenter가 최대 5개까지 자동 확장
    max_size     = 5
  }

  update_config {
    # 업데이트 시 한 번에 1개 노드만 중단 (서비스 영향 최소화)
    max_unavailable = 1
  }

  labels = {
    role = "worker"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr,
  ]

  tags = {
    Name                                        = "${var.project_name}-worker"
    Project                                     = var.project_name
    # Karpenter가 이 태그로 관리할 노드 탐색
    "karpenter.sh/discovery"                    = var.project_name
    # 이 노드가 해당 EKS 클러스터 소속임을 표시
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned"
  }
}

# ----------------------------------------
# Karpenter Node Access Entry
# Karpenter가 생성하는 노드가 EKS 클러스터에 합류할 수 있도록
# aws-auth ConfigMap 수동 편집 대신 Terraform으로 자동화
# ----------------------------------------

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"

  depends_on = [aws_eks_cluster.main]
}

# aws-auth ConfigMap은 EKS 관리형 Node Group이 자동으로 업데이트
# Karpenter 노드는 aws_eks_access_entry로 처리
# → Terraform에서 별도 관리 불필요

# ----------------------------------------
# GitHub Actions 배포 역할 접근 허용
# terraform apply를 실행한 역할 외에 깃액션 역할도 클러스터 접근 가능하도록 추가
# ----------------------------------------

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.github_actions_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.github_actions.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ----------------------------------------
# 로컬 kubeconfig 자동 갱신
# terraform apply 후 클러스터 엔드포인트가 바뀌면 자동으로 kubeconfig를 업데이트
# ----------------------------------------

resource "null_resource" "update_kubeconfig" {
  depends_on = [aws_eks_cluster.main]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
  }

  triggers = {
    cluster_endpoint = aws_eks_cluster.main.endpoint
  }
}