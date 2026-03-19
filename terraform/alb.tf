########################################
# ALB (Application Load Balancer)
# aws_lb.main 리소스는 제거됨.
# ALB 전체 라이프사이클(생성·리스너·타겟그룹·삭제)은
# AWS Load Balancer Controller(LBC)가 k8s/aws-lbc/ingress.yaml의
# Ingress 어노테이션을 통해 단독 관리함.
# terraform이 ALB를 미리 생성하면 DuplicateLoadBalancerName 충돌 발생.
########################################