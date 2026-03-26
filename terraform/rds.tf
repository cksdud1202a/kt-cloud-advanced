# ----------------------------------------
# rds.tf
# DR RDS - 온프레미스 장애 시 DB 역할을 대신하는 MySQL
# ----------------------------------------

########################################
# RDS Subnet Group
########################################

# RDS가 배치될 서브넷 그룹
# RDS는 private 서브넷끼리 묶어야 보안상 맞음
# private2는 비어있지만 AWS 2개 AZ 요구사항 충족용
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private2.id]

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

  engine         = "mysql"
  engine_version = "8.0"

  # db.t3.micro = 최소 스펙 (Warm Standby → 비용 절감)
  instance_class = "db.t3.micro"

  # 초기 20GB, 부족하면 자동으로 최대 100GB까지 확장
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"

  db_name  = "appdb"
  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # DMS CDC 복제 수신을 위해 바이너리 로그 활성화
  parameter_group_name = aws_db_parameter_group.mysql.name

  # 매일 03:00~04:00 UTC 자동 백업, 1일 보관(프리티어 최대 제한)
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # 테스트 환경 → 삭제 보호 끔
  # 실제 운영이면 true로 변경 필요
  deletion_protection = false
  skip_final_snapshot = true

  # Warm Standby → 단일 AZ 유지 (비용 절감)
  # multi_az = true 하면 비용 2배
  multi_az = false

  # 외부 인터넷 접근 차단
  publicly_accessible = false

  tags = {
    Name    = "${var.project_name}-dr-rds"
    Project = var.project_name
  }
}

########################################
# RDS Parameter Group
########################################

# DMS CDC 복제를 위한 바이너리 로그 설정
# 바이너리 로그 = MySQL이 모든 변경사항을 기록하는 로그
# DMS가 이 로그를 읽어서 온프레미스 변경사항을 RDS에 반영
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project_name}-mysql-params"
  family = "mysql8.0"

  # ROW = 변경된 행 데이터 전체 기록 (DMS CDC 필수 형식)
  # STATEMENT 형식은 SQL문만 기록해서 CDC에 부적합
  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "immediate" # dynamic 파라미터 — 재부팅 없이 즉시 적용
  }

  tags = {
    Name    = "${var.project_name}-mysql-params"
    Project = var.project_name
  }
}