#######################################
# ALB (Application Load Balancer)
# aws_lb.main 리소스는 제거됨.
# ALB 전체 라이프사이클(생성·리스너·타겟그룹·삭제)은
# AWS Load Balancer Controller(LBC)가 k8s/aws-lbc/ingress.yaml의
# Ingress 어노테이션을 통해 단독 관리함.
# terraform이 ALB를 미리 생성하면 DuplicateLoadBalancerName 충돌 발생.
######################################

#######################################
# Destroy-time cleanup
# LBC/EKS/Karpenter가 생성한 외부 리소스는 Terraform 관리 밖이므로
# terraform destroy 시 null_resource provisioner로 먼저 삭제
#
# 실행 순서 (depends_on 역방향):
#   1. aws_eks_cluster/node_group 삭제 (eks.tf의 depends_on으로 cleanup보다 먼저)
#   2. [이 null_resource] cleanup 실행 (Karpenter 노드 종료, ALB/TG/SG/ENI 정리)
#   3. aws_subnet.public/public2 삭제
#
# DMS task 중지는 dms.tf의 aws_dms_replication_task.cdc에 직접 달린
# destroy provisioner가 처리 (retry 시에도 반드시 실행됨)
#######################################

resource "null_resource" "cleanup_k8s_resources" {
  # public 서브넷에 의존 → destroy 시 서브넷보다 먼저 실행됨
  depends_on = [
    aws_subnet.public,
    aws_subnet.public2,
  ]

  triggers = {
    vpc_id       = aws_vpc.main.id
    region       = var.region
    alb_name     = "${var.project_name}-alb"
    project_name = var.project_name
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

      # LBC가 생성한 Target Group 삭제
      # ALB 삭제 후에야 Target Group 삭제 가능 (ALB에 연결된 상태면 삭제 불가)
      # Target Group은 VPC에 묶여있어서 삭제 안 하면 VPC 삭제 시 DependencyViolation 발생
      echo "Deleting LBC-created target groups..."
      TG_ARNS=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?VpcId=='${self.triggers.vpc_id}'].TargetGroupArn" \
        --output text --region ${self.triggers.region} 2>/dev/null)
      for TG_ARN in $TG_ARNS; do
        echo "  Deleting target group: $TG_ARN"
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN" \
          --region ${self.triggers.region} || true
      done

      # Karpenter가 생성한 EC2 노드 terminate
      # EKS cluster 삭제 후 Karpenter controller가 종료되면 Karpenter 노드는 스스로 terminate 못 함
      # 이 노드들이 public IP를 가지고 있으면 IGW detach 시 DependencyViolation 발생
      echo "Terminating Karpenter-managed EC2 instances..."
      KARPENTER_INSTANCES=$(aws ec2 describe-instances \
        --filters \
          "Name=tag-key,Values=karpenter.sh/nodepool" \
          "Name=vpc-id,Values=${self.triggers.vpc_id}" \
          "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text --region ${self.triggers.region})

      if [ -n "$KARPENTER_INSTANCES" ]; then
        echo "  Terminating: $KARPENTER_INSTANCES"
        aws ec2 terminate-instances \
          --instance-ids $KARPENTER_INSTANCES \
          --region ${self.triggers.region}
        aws ec2 wait instance-terminated \
          --instance-ids $KARPENTER_INSTANCES \
          --region ${self.triggers.region}
        echo "  Karpenter instances terminated."
      else
        echo "  No Karpenter instances found."
      fi

      # ALB/Karpenter 노드 삭제 후 ENI 해제 대기
      echo "Waiting 30s for ENI/SG dependencies to clear..."
      sleep 30

      # Orphaned ENI 삭제 (available 상태 = 아무것도 붙어있지 않은 ENI)
      # EKS CNI, DMS, RDS 삭제 후 남은 ENI가 서브넷에 있으면 서브넷 삭제 실패
      echo "Deleting orphaned ENIs..."
      ORPHAN_ENIS=$(aws ec2 describe-network-interfaces \
        --filters \
          "Name=vpc-id,Values=${self.triggers.vpc_id}" \
          "Name=status,Values=available" \
        --query "NetworkInterfaces[*].NetworkInterfaceId" \
        --output text --region ${self.triggers.region})
      for ENI in $ORPHAN_ENIS; do
        echo "  Deleting ENI: $ENI"
        aws ec2 delete-network-interface --network-interface-id "$ENI" \
          --region ${self.triggers.region} || true
      done

      # VPC 내 default 제외한 전체 SG 목록 조회
      ALL_SGS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text --region ${self.triggers.region})

      # SG 간 cross-reference 인바운드 규칙 전부 revoke
      # (EKS cluster SG ↔ worker SG, k8s-traffic SG 등 서로 참조 시 DependencyViolation 방지)
      echo "Revoking cross-SG inbound rules..."
      for SG_ID in $ALL_SGS; do
        for REF_SG in $ALL_SGS; do
          RULES=$(aws ec2 describe-security-groups \
            --group-ids "$SG_ID" \
            --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$REF_SG']]" \
            --output json --region ${self.triggers.region} 2>/dev/null)
          if [ -n "$RULES" ] && [ "$RULES" != "[]" ]; then
            echo "  Revoking inbound in $SG_ID referencing $REF_SG"
            aws ec2 revoke-security-group-ingress \
              --group-id "$SG_ID" \
              --ip-permissions "$RULES" \
              --region ${self.triggers.region} || true
          fi
        done
      done

      # Terraform 외부 SG 삭제: k8s-* 와 eks-cluster-sg-*
      # - k8s-*            : LBC(Load Balancer Controller)가 생성한 SG
      # - eks-cluster-sg-* : EKS가 자동 생성한 cluster SG (EKS 삭제 후에도 잔존 가능)
      # 이 두 SG가 남아있으면 Terraform이 관리하는 worker-sg 등을 삭제 못 함
      # starts_with()는 AWS CLI JMESPath 미지원 → --filters Name=group-name 으로 각각 조회
      EXTERNAL_SGS=$(
        aws ec2 describe-security-groups \
          --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" "Name=group-name,Values=k8s-*" \
          --query "SecurityGroups[*].GroupId" \
          --output text --region ${self.triggers.region}
        aws ec2 describe-security-groups \
          --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" "Name=group-name,Values=eks-cluster-sg-*" \
          --query "SecurityGroups[*].GroupId" \
          --output text --region ${self.triggers.region}
      )
      for SG_ID in $EXTERNAL_SGS; do
        echo "Deleting external SG: $SG_ID"
        for i in 1 2 3 4 5; do
          aws ec2 delete-security-group --group-id "$SG_ID" --region ${self.triggers.region} && break
          echo "  Attempt $i failed, retrying in 15s..."
          sleep 15
        done
      done
    EOT
  }
}