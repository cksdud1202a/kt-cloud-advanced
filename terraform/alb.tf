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
#
# 실행 순서 (depends_on 역방향):
#   1. pre_destroy: kubectl delete ingress → LBC가 ALB/TG/k8s-SG 정리
#   2. aws_eks_cluster/node_group 삭제
#   3. cleanup_k8s_resources: Karpenter 노드 종료, ENI/SG 정리
#   4. aws_subnet.public/public2 삭제
#
# DMS task 중지는 dms.tf의 aws_dms_replication_task.cdc destroy provisioner가 처리
#######################################

# 1단계: Ingress 삭제 → LBC가 ALB/TG/k8s-SG 정리하도록 위임
# eks_cluster/node_group/cleanup에 depends_on → destroy 시 가장 먼저 실행
# (kubectl이 동작하려면 EKS가 살아있어야 하므로 EKS 삭제 전에 실행되어야 함)
resource "null_resource" "pre_destroy" {
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.worker,
    null_resource.cleanup_k8s_resources,
  ]

  triggers = {
    region   = var.region
    alb_name = "${var.project_name}-alb"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Deleting Ingress (LBC가 ALB/TG/SG 정리)..."
      timeout 30 kubectl delete ingress hybrid-dr-ingress --ignore-not-found 2>/dev/null || true

      echo "ALB 삭제 대기 중..."
      for i in $(seq 1 12); do
        ALB_ARN=$(aws elbv2 describe-load-balancers \
          --names "${self.triggers.alb_name}" \
          --query "LoadBalancers[0].LoadBalancerArn" \
          --output text --region ${self.triggers.region} 2>/dev/null)
        if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
          echo "ALB 삭제 완료."
          break
        fi
        echo "  대기 중... ($i/12)"
        sleep 10
      done
    EOT
  }
}

# 2단계: EKS 삭제 후 남은 리소스 정리
# LBC가 이미 ALB/TG/k8s-SG를 정리했으므로 Karpenter 노드/ENI/eks-cluster-sg만 처리
resource "null_resource" "cleanup_k8s_resources" {
  # depends_on에 IGW 추가 → destroy 시 cleanup이 IGW보다 먼저 실행됨
  # (A depends_on B → destroy 시 A가 B보다 먼저 삭제)
  # cleanup 스크립트에서 모든 EC2 종료 + IGW 삭제 후 Terraform이 IGW 삭제 시도 → 이미 없으므로 즉시 완료
  depends_on = [
    aws_subnet.public,
    aws_subnet.public2,
    aws_internet_gateway.igw,
  ]

  triggers = {
    vpc_id  = aws_vpc.main.id
    igw_id  = aws_internet_gateway.igw.id
    region  = var.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # VPC 내 모든 EC2 종료 (공인 IP 해제 → IGW detach 가능)
      # monitoring, worker node, Karpenter node 모두 포함
      echo "Terminating all EC2 instances in VPC..."
      ALL_INSTANCES=$(aws ec2 describe-instances \
        --filters \
          "Name=vpc-id,Values=${self.triggers.vpc_id}" \
          "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text --region ${self.triggers.region})
      if [ -n "$ALL_INSTANCES" ]; then
        echo "  Terminating: $ALL_INSTANCES"
        aws ec2 terminate-instances --instance-ids $ALL_INSTANCES --region ${self.triggers.region}
        aws ec2 wait instance-terminated --instance-ids $ALL_INSTANCES --region ${self.triggers.region}
        echo "  All EC2 instances terminated."
      else
        echo "  No EC2 instances found."
      fi

      echo "Waiting 10s for ENI/SG dependencies to clear..."
      sleep 10

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

      ALL_SGS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text --region ${self.triggers.region})

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

      # eks-cluster-sg-*: EKS가 자동 생성, EKS 삭제 후에도 잔존
      # k8s-*: LBC가 생성한 SG (k8s-default-*, k8s-traffic-*), ingress 삭제 후에도 잔존하는 경우 있음
      echo "Deleting eks-cluster-sg-* and k8s-* SGs..."
      EKS_SGS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" \
        --query "SecurityGroups[?starts_with(GroupName,'eks-cluster-sg-') || starts_with(GroupName,'k8s-')].GroupId" \
        --output text --region ${self.triggers.region})
      for SG_ID in $EKS_SGS; do
        echo "  Deleting SG: $SG_ID"
        for i in 1 2 3 4 5; do
          aws ec2 delete-security-group --group-id "$SG_ID" --region ${self.triggers.region} && break
          echo "  Attempt $i failed, retrying in 15s..."
          sleep 15
        done
      done

      # IGW 명시적 삭제: 이후 Terraform이 IGW 삭제 시도 시 이미 없으므로 즉시 완료
      echo "Detaching and deleting IGW..."
      aws ec2 detach-internet-gateway \
        --internet-gateway-id ${self.triggers.igw_id} \
        --vpc-id ${self.triggers.vpc_id} \
        --region ${self.triggers.region} 2>/dev/null || true
      aws ec2 delete-internet-gateway \
        --internet-gateway-id ${self.triggers.igw_id} \
        --region ${self.triggers.region} 2>/dev/null || true
      echo "IGW 삭제 완료 (또는 이미 삭제됨)"
    EOT
  }
}