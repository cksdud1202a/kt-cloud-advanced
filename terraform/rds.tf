########################################
# RDS Subnet Group
########################################

# RDS가 배치될 서브넷 그룹
# Private Subnet에 배치 (외부 인터넷 차단)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  # RDS는 최소 2개 AZ 서브넷 필요
  subnet_ids = [aws_subnet.private.id, aws_subnet.public.id]

  tags = {
    Name    = "${var.project_name}-rds-subnet-group"
    Project = var.project_name
  }
}

########################################
# DR RDS (MySQL)
########################################

resource "aws_db_instance" "dr_rds" {
  identifier = "${var.project_name}-dr-rds"

  # MySQL 엔진
  engine         = "mysql"
  engine_version = "8.0"

  # 인스턴스 타입 (최소 스펙 - Warm Standby)
  instance_class = "db.t3.micro"

  # 스토리지 설정
  allocated_storage     = 20    # 최소 20GB
  max_allocated_storage = 100   # 자동 확장 최대 100GB
  storage_type          = "gp2"

  # DB 설정
  db_name  = "appdb"
  username = "admin"
  password = var.db_password

  # 서브넷 그룹 적용
  db_subnet_group_name = aws_db_subnet_group.main.name

  # Security Group 적용
  vpc_security_group_ids = [aws_security_group.rds.id]

  # 온프레미스 MySQL CDC 복제 수신을 위해 바이너리 로그 활성화
  parameter_group_name = aws_db_parameter_group.mysql.name

  # 백업 설정
  backup_retention_period = 7      # 7일 백업 보관
  backup_window           = "03:00-04:00"  # 백업 시간 (UTC)
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # 삭제 보호 비활성화 (테스트 환경)
  deletion_protection = false

  # terraform destroy 시 스냅샷 없이 삭제
  skip_final_snapshot = true

  # Multi-AZ 비활성화 (비용 절감 - Warm Standby니까)
  multi_az = false

  # 퍼블릭 접근 차단
  publicly_accessible = false

  tags = {
    Name    = "${var.project_name}-dr-rds"
    Project = var.project_name
  }
}

########################################
# RDS Parameter Group
########################################

# DMS CDC를 위해 바이너리 로그 활성화
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project_name}-mysql-params"
  family = "mysql8.0"

  # 바이너리 로그 형식 설정 (CDC 복제에 필요)
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  # 바이너리 로그 보관 기간 (시간 단위)
  parameter {
    name  = "binlog_retention_hours"  
    value = "24"
  }

  tags = {
    Name    = "${var.project_name}-mysql-params"
    Project = var.project_name
  }
}