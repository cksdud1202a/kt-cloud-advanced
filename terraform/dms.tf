# ----------------------------------------
# dms.tf
# DMS CDC - 온프레미스 MySQL → DR RDS 실시간 복제
# ----------------------------------------

########################################
# DMS Replication Subnet Group
########################################

# DMS도 private 서브넷끼리 묶어야 보안상 맞음
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.project_name}-dms-subnet-group"
  replication_subnet_group_description = "DMS subnet group for hybrid-dr"
  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private2.id
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
# 온프레미스 MySQL 읽어서 → DR RDS에 쓰는 역할
resource "aws_dms_replication_instance" "main" {
  replication_instance_id    = "${var.project_name}-dms-instance"
  replication_instance_class = "dms.t3.medium"

  # 단일 AZ (비용 절감)
  multi_az = false

  # 외부 접근 차단
  publicly_accessible = false

  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids      = [aws_security_group.dms.id]

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
# Tailscale VPN으로 연결되는 온프레미스 서버 IP 사용
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-source-mysql"
  endpoint_type = "source"
  engine_name   = "mysql"

  # 모니터링 EC2의 socat 프록시 경유 (EC2:3306 → 온프레미스 MySQL:30306)
  # DMS SG는 Tailscale IP(100.x.x.x)로 직접 연결 불가 → EC2 프록시 사용
  server_name = aws_instance.monitoring.private_ip
  port        = 3306
  username    = "root"
  password    = var.onprem_mysql_password

  tags = {
    Name    = "${var.project_name}-source-mysql"
    Project = var.project_name
  }
}

########################################
# DMS Target Endpoint (DR RDS)
########################################

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.project_name}-target-rds"
  endpoint_type = "target"
  engine_name   = "mysql"

  # Terraform이 RDS 생성 후 자동으로 엔드포인트 주소 가져옴
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
# full-load = 처음에 전체 데이터 복사
# cdc = 이후 변경사항만 실시간 반영
resource "aws_dms_replication_task" "cdc" {
  replication_task_id = "${var.project_name}-cdc-task"
  migration_type      = "full-load-and-cdc"

  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn

  # 전체 DB 복제 (모든 스키마, 모든 테이블)
  table_mappings = jsonencode({
    rules = [{
      rule-type = "selection"
      rule-id   = "1"
      rule-name = "1"
      object-locator = {
        schema-name = "%"
        table-name  = "%"
      }
      rule-action = "include"
    }]
  })

  tags = {
    Name    = "${var.project_name}-cdc-task"
    Project = var.project_name
  }

  # running 상태의 task는 AWS API가 삭제를 거부함
  # Terraform provider가 자동 stop을 안 하므로 destroy 전에 직접 중지
  # aws_dms_replication_task 리소스 자체에 달아서 retry 시에도 반드시 실행됨
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Stopping DMS replication task..."
      TASK_ARN=$(aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=${self.replication_task_id}" \
        --query "ReplicationTasks[0].ReplicationTaskArn" \
        --output text --region ap-northeast-2 2>/dev/null)

      if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
        echo "  DMS task not found, skipping."
        exit 0
      fi

      STATUS=$(aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=${self.replication_task_id}" \
        --query "ReplicationTasks[0].Status" \
        --output text --region ap-northeast-2 2>/dev/null)

      if [ "$STATUS" != "running" ]; then
        echo "  DMS task not running (status: $STATUS), skipping."
        exit 0
      fi

      echo "  Stopping DMS task: $TASK_ARN"
      aws dms stop-replication-task \
        --replication-task-arn "$TASK_ARN" \
        --region ap-northeast-2 || true

      for i in $(seq 1 18); do
        STATUS=$(aws dms describe-replication-tasks \
          --filters "Name=replication-task-id,Values=${self.replication_task_id}" \
          --query "ReplicationTasks[0].Status" \
          --output text --region ap-northeast-2 2>/dev/null)
        [ "$STATUS" = "stopped" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "None" ] && break
        echo "  Waiting for DMS task to stop (status: $STATUS)..."
        sleep 10
      done
      echo "  DMS task stopped."
    EOT
  }
}