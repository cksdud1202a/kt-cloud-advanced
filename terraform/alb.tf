#######################################
# ALB (Application Load Balancer)
# aws_lb.main 리소스는 제거됨.
# ALB 전체 라이프사이클(생성·리스너·타겟그룹·삭제)은
# AWS Load Balancer Controller(LBC)가 k8s/aws-lbc/ingress.yaml의
# Ingress 어노테이션을 통해 단독 관리함.
# terraform이 ALB를 미리 생성하면 DuplicateLoadBalancerName 충돌 발생.
#######################################

#######################################
# Destroy-time cleanup
# LBC/EKS가 생성한 ALB와 K8s 보안그룹은 Terraform 외부 리소스이므로
# terraform destroy 시 null_resource provisioner로 먼저 삭제
#######################################

resource "null_resource" "cleanup_k8s_resources" {
  # public 서브넷에 의존 → destroy 시 서브넷보다 먼저 실행됨
  depends_on = [
    aws_subnet.public,
    aws_subnet.public2,
  ]

  triggers = {
    vpc_id   = aws_vpc.main.id
    region   = var.region
    alb_name = "${var.project_name}-alb"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # ALB 삭제 (없으면 스킵)
      ALB_ARN=$(aws elbv2 describe-load-balancers \
        --names "${self.triggers.alb_name}" \
        --query "LoadBalancers[0].LoadBalancerArn" \
        --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
        echo "Deleting ALB: $ALB_ARN"
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region ${self.triggers.region}
        aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" --region ${self.triggers.region}
        echo "ALB deleted."
      else
        echo "ALB not found, skipping."
      fi

      # K8s가 생성한 보안그룹 삭제 (이름이 k8s- 로 시작하는 것)
      for SG_ID in $(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" "Name=group-name,Values=k8s-*" \
        --query "SecurityGroups[*].GroupId" \
        --output text --region ${self.triggers.region}); do
        echo "Deleting SG: $SG_ID"
        aws ec2 delete-security-group --group-id "$SG_ID" --region ${self.triggers.region} || true
      done
    EOT
  }
}