# ----------------------------------------
# network.tf
# VPC, 서브넷, IGW, 라우팅 테이블 정의
# ----------------------------------------

# VPC 생성
# enable_dns_hostnames = EC2에 DNS 이름 자동 부여 (EKS 필수)
# enable_dns_support   = VPC 내부 DNS 해석 활성화 (EKS 필수)
resource "aws_vpc" "main" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc", Project = var.project_name }
}

# Internet Gateway 생성 및 VPC 연결
# IGW = VPC와 인터넷 사이의 문
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# 현재 리전에서 사용 가능한 AZ 목록 자동 조회
# names[0] = ap-northeast-2a
# names[1] = ap-northeast-2b
data "aws_availability_zones" "available" {
  state = "available"
}

# ----------------------------------------
# Public 서브넷
# ----------------------------------------

# Public Subnet 1 (AZ-a) - Worker Node + Karpente + ALB 2개 AZ 요구사항 충족
# kubernetes.io/role/elb = ALB가 이 서브넷 자동 인식
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.project_name}-public-subnet-1"
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned"
    "kubernetes.io/role/elb"                    = "1"
    "karpenter.sh/discovery"                    = var.project_name
  }

  # Retry 안전망: cleanup_k8s_resources null_resource가 이미 실행됐더라도
  # 서브넷 삭제가 실패하면 이 provisioner가 재실행되어 남은 리소스를 정리함.
  # self.vpc_id로 VPC 내 전체 리소스를 대상으로 처리.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      VPC_ID="${self.vpc_id}"
      REGION="ap-northeast-2"

      # 남은 Karpenter EC2 노드 terminate
      echo "Terminating remaining Karpenter nodes..."
      INSTANCES=$(aws ec2 describe-instances \
        --filters \
          "Name=tag-key,Values=karpenter.sh/nodepool" \
          "Name=vpc-id,Values=$VPC_ID" \
          "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text --region $REGION)
      if [ -n "$INSTANCES" ]; then
        aws ec2 terminate-instances --instance-ids $INSTANCES --region $REGION
        aws ec2 wait instance-terminated --instance-ids $INSTANCES --region $REGION
      fi

      # 남은 Target Group 삭제
      echo "Deleting remaining target groups..."
      TG_ARNS=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
        --output text --region $REGION 2>/dev/null)
      for TG_ARN in $TG_ARNS; do
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region $REGION || true
      done

      # 남은 available ENI 삭제
      echo "Deleting remaining available ENIs..."
      ENIS=$(aws ec2 describe-network-interfaces \
        --filters \
          "Name=vpc-id,Values=$VPC_ID" \
          "Name=status,Values=available" \
        --query "NetworkInterfaces[*].NetworkInterfaceId" \
        --output text --region $REGION)
      for ENI in $ENIS; do
        aws ec2 delete-network-interface --network-interface-id "$ENI" --region $REGION || true
      done

      # SG 간 cross-reference inbound 규칙 revoke
      echo "Revoking remaining cross-SG inbound rules..."
      ALL_SGS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text --region $REGION)
      for SG_ID in $ALL_SGS; do
        for REF_SG in $ALL_SGS; do
          RULES=$(aws ec2 describe-security-groups \
            --group-ids "$SG_ID" \
            --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$REF_SG']]" \
            --output json --region $REGION 2>/dev/null)
          if [ -n "$RULES" ] && [ "$RULES" != "[]" ]; then
            aws ec2 revoke-security-group-ingress \
              --group-id "$SG_ID" --ip-permissions "$RULES" --region $REGION || true
          fi
        done
      done

      # 외부 SG 삭제 (k8s-*, eks-cluster-sg-*)
      echo "Deleting remaining external SGs..."
      EXTERNAL_SGS=$(
        aws ec2 describe-security-groups \
          --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=k8s-*" \
          --query "SecurityGroups[*].GroupId" --output text --region $REGION
        aws ec2 describe-security-groups \
          --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=eks-cluster-sg-*" \
          --query "SecurityGroups[*].GroupId" --output text --region $REGION
      )
      for SG_ID in $EXTERNAL_SGS; do
        for i in 1 2 3 4 5; do
          aws ec2 delete-security-group --group-id "$SG_ID" --region $REGION && break
          sleep 15
        done
      done
    EOT
  }
}

# Public Subnet 2 (AZ-b) - Worker Node + Karpente + ALB 2개 AZ 요구사항 충족
resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.project_name}-public-subnet-2"
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned"
    "kubernetes.io/role/elb"                    = "1"
    "karpenter.sh/discovery"                    = var.project_name
  }
}

# Public Subnet 3 (AZ-c) - Monitoring EC2
# 클러스터 태그 없음 = Worker Node 배치 안 함
resource "aws_subnet" "public3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.5.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet-3"
  }
}

# ----------------------------------------
# Private 서브넷
# ----------------------------------------

# Private Subnet 1 (AZ-a) - RDS, EFS 전용
# Worker Node와 같은 AZ → 크로스 AZ 비용 없음
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "${var.project_name}-private-subnet-1" }
}

# Private Subnet 2 (AZ-b)
# RDS/DMS 서브넷 그룹 최소 2개 AZ 요구사항 충족용
# 실제 리소스 없음 (비어있는 서브넷)
resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = { Name = "${var.project_name}-private-subnet-2" }
}

# ----------------------------------------
# 라우팅 테이블
# ----------------------------------------

# Public 라우팅 테이블
# 0.0.0.0/0 → IGW = 모든 트래픽을 인터넷으로
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

# Public 서브넷 1 → Public 라우팅 테이블
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Public 서브넷 2 → Public 라우팅 테이블
resource "aws_route_table_association" "public2_assoc" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public_rt.id
}

# Public 서브넷 3 → Public 라우팅 테이블
resource "aws_route_table_association" "public3_assoc" {
  subnet_id      = aws_subnet.public3.id
  route_table_id = aws_route_table.public_rt.id
}

# Private 라우팅 테이블
# 외부로 나가는 route 없음 = 인터넷 차단
# VPC 내부 통신만 가능 (EKS → RDS, EKS → EFS)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

# DMS → Tailscale IP(100.64.0.0/10) 라우트
# DMS가 온프레미스 MySQL(Tailscale IP)에 접근할 때
# 모니터링 EC2(Tailscale Subnet Router)를 경유하도록 설정
resource "aws_route" "private_to_tailscale" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "100.64.0.0/10"
  network_interface_id   = aws_instance.monitoring.primary_network_interface_id
}

# Private 서브넷 1 → Private 라우팅 테이블
resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}

# Private 서브넷 2 → Private 라우팅 테이블
resource "aws_route_table_association" "private2_assoc" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private_rt.id
}