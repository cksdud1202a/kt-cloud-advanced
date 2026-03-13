########################################
# DMS Replication Subnet Group
########################################

# DMS가 사용할 서브넷 그룹
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.project_name}-dms-subnet-group"
  replication_subnet_group_description = "DMS subnet group for hybrid-dr"
  subnet_ids = [
    aws_subnet.public.id,
    aws_subnet.private.id
  ]

  tags = {
    Name    = "${var.project_name}-dms-subnet-group"
    Project = var.project_name
  }
}

########################################
# DMS Replication Instance
########################################

# DMS가 실제로 데이터 복제 작업을 수행하는 인스턴스
resource "aws_dms_replication_instance" "main" {
  replication_instance_id    = "${var.project_name}-dms-instance"
  replication_instance_class = "dms.t3.micro"  # 최소 스펙

  # 단일 AZ (비용 절감)
  multi_az = false

  # Public 접근 차단
  publicly_accessible = false

  # 서브넷 그룹 적용
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id

  # Security Group 적용
  vpc_security_group_ids = [aws_security_group.rds.id]

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc,
    aws_iam_role_policy_attachment.dms_cloudwatch,
  ]

  tags = {
    Name    = "${var.project_name}-dms-instance"
    Project = var.project_name
  }
}

########################################
# DMS Source Endpoint (온프레미스 MySQL)
########################################

# 온프레미스 MySQL을 CDC 소스로 설정
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-source-mysql"
  endpoint_type = "source"
  engine_name   = "mysql"

  # 온프레미스 MySQL 접속 정보
  # Tailscale VPN으로 연결되는 온프레미스 MySQL IP
  server_name = var.onprem_mysql_ip
  port        = 3306
  username    = "repl_user"  # 복제 전용 계정
  password    = var.db_password

  tags = {
    Name    = "${var.project_name}-source-mysql"
    Project = var.project_name
  }
}

########################################
# DMS Target Endpoint (DR RDS)
########################################

# DR RDS를 CDC 타겟으로 설정
resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.project_name}-target-rds"
  endpoint_type = "target"
  engine_name   = "mysql"

  # DR RDS 접속 정보
  server_name = aws_db_instance.dr_rds.address
  port        = 3306
  username    = "admin"
  password    = var.db_password

  tags = {
    Name    = "${var.project_name}-target-rds"
    Project = var.project_name
  }
}

########################################
# DMS Replication Task (CDC)
########################################

# 온프레미스 MySQL → DR RDS CDC 복제 태스크
resource "aws_dms_replication_task" "cdc" {
  replication_task_id      = "${var.project_name}-cdc-task"
  migration_type           = "cdc"  # Change Data Capture

  # 소스, 타겟, 복제 인스턴스 연결
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn

  # 복제할 테이블 설정 (전체 DB 복제)
  table_mappings = jsonencode({
    rules = [{
      rule-type = "selection"
      rule-id   = "1"
      rule-name = "1"
      object-locator = {
        schema-name = "%"  # 모든 스키마
        table-name  = "%"  # 모든 테이블
      }
      rule-action = "include"
    }]
  })

  tags = {
    Name    = "${var.project_name}-cdc-task"
    Project = var.project_name
  }
}