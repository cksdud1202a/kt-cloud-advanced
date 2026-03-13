output "eks_cluster_endpoint" {
  description = "EKS API Server 엔드포인트 (kubectl 설정에 사용)"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.main.name
}

output "monitoring_public_ip" {
  description = "Monitoring EC2 퍼블릭 IP (Grafana, Prometheus 접근용)"
  value       = aws_instance.monitoring.public_ip
}

output "rds_endpoint" {
  description = "DR RDS 엔드포인트 (DMS CDC 타겟 설정에 사용)"
  value       = aws_db_instance.dr_rds.address
}

output "efs_id" {
  description = "EFS ID (K8s PersistentVolume 설정에 사용)"
  value       = aws_efs_file_system.main.id
}

output "alb_dns" {
  description = "ALB DNS (Route 53 Failover 레코드에 사용)"
  value       = aws_lb.main.dns_name
}