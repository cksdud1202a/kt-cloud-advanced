########################################
# EFS File System
########################################

# EFS 파일 시스템 생성
# 온프레미스 NFS 데이터를 DR 환경에서도 사용하기 위한 공유 스토리지
resource "aws_efs_file_system" "main" {
  # 암호화 활성화
  encrypted = true

  # 성능 모드 (일반 웹 서비스용)
  performance_mode = "generalPurpose"

  # 처리량 모드 (버스팅 - 비용 절감)
  throughput_mode = "bursting"

  # 30일 이상 접근 안 한 파일은 저렴한 스토리지로 자동 이동
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name    = "${var.project_name}-efs"
    Project = var.project_name
  }
}

########################################
# EFS Mount Target
########################################

# EFS를 Private Subnet에서 마운트할 수 있도록 Mount Target 생성
# Worker Node가 EFS에 접근할 때 사용하는 엔드포인트
resource "aws_efs_mount_target" "private" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.efs.id]
}

########################################
# EFS Security Group
########################################

# EFS 전용 Security Group
resource "aws_security_group" "efs" {
  name   = "${var.project_name}-efs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049  # NFS 포트
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-efs-sg" }
}