resource "aws_vpc" "main" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# 현재 리전에서 사용 가능한 가용영역(AZ) 목록 가져옴
# ex) ap-northeast-2a, ap-northeast-2b, ap-northeast-2c
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnet (Worker Node, Monitoring EC2)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]  # ap-northeast-2a
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "${var.project_name}-public-subnet"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
    "kubernetes.io/role/elb"                    = "1"  # 이거 추가
  }
}

# Private Subnet (DR RDS, EFS)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]  # ap-northeast-2b
  tags = { Name = "${var.project_name}-private-subnet" }
}

# Public Route Table (IGW로 인터넷 연결)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Route Table (인터넷 연결 없음, VPC 내부 통신만)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}