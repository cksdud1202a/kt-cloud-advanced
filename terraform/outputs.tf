# ----------------------------------------
# outputs.tf
# terraform apply 후 필요한 값들 출력
# GitHub Actions, Ansible, k8s 설정에서 참조
# ----------------------------------------

# kubectl 설정에 사용
# aws eks update-kubeconfig --name <eks_cluster_name>
output "eks_cluster_endpoint" {
  description = "EKS API Server 엔드포인트"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.main.name
}

# Karpenter Helm 설치 시 필요
output "eks_cluster_version" {
  description = "EKS 클러스터 K8s 버전"
  value       = aws_eks_cluster.main.version
}

# Karpenter IRSA 설정 시 필요
output "eks_oidc_provider_arn" {
  description = "EKS OIDC Provider ARN (Karpenter IRSA 설정에 사용)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# Karpenter Helm values에 필요
output "karpenter_controller_role_arn" {
  description = "Karpenter Controller IAM Role ARN"
  value       = aws_iam_role.karpenter_controller.arn
}

# Karpenter EC2NodeClass에 필요
output "karpenter_node_instance_profile" {
  description = "Karpenter가 생성하는 노드에 적용할 Instance Profile 이름"
  value       = aws_iam_instance_profile.karpenter_node.name
}

# Ansible hosts.ini에 사용
# Monitoring EC2 SSH 접속 IP
output "monitoring_public_ip" {
  description = "Monitoring EC2 퍼블릭 IP (Ansible hosts.ini에 사용)"
  value       = aws_instance.monitoring.public_ip
}

# DMS CDC 타겟 설정에 사용
output "rds_endpoint" {
  description = "DR RDS 엔드포인트"
  value       = aws_db_instance.dr_rds.address
}

# K8s PersistentVolume 설정에 사용
output "efs_id" {
  description = "EFS ID"
  value       = aws_efs_file_system.main.id
}

# Route 53 Failover Secondary 레코드에 사용
# LBC 배포 전에는 "" (기본값), 배포 후 -var="alb_dns=..." 로 주입
output "alb_dns" {
  description = "LBC가 생성한 ALB DNS (var.alb_dns 입력값 그대로 출력)"
  value       = var.alb_dns
}

# GitHub Actions에서 kubeconfig 설정 시 필요
output "aws_region" {
  description = "AWS 리전"
  value       = var.region
}

# AWS Load Balancer Controller Helm values에 필요
output "aws_lbc_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.aws_lbc.arn
}

# LBC Helm values의 __VPC_ID__ 치환에 필요
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
