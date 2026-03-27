# ----------------------------------------
# s3.tf
# 백업 및 장기 보관용 S3 bucket 생성
# 현재 프로젝트에서는 운영 스토리지(EFS, RDS)와 분리해서
# 백업/아카이브 용도로만 사용
# ----------------------------------------

locals {
  # S3 bucket 이름은 전역 유일해야 하므로 account_id를 붙여서 충돌 방지
  backup_bucket_name = "${var.project_name}-backup-${data.aws_caller_identity.current.account_id}"
}

# 백업용 S3 bucket
resource "aws_s3_bucket" "backup" {
  bucket = local.backup_bucket_name

  tags = {
    Name    = local.backup_bucket_name
    Project = var.project_name
    Purpose = "backup"
  }
}

# 버전 관리 활성화
# 파일이 덮어써지거나 삭제돼도 복구 가능
resource "aws_s3_bucket_versioning" "backup_versioning" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 서버사이드 암호화 적용
# 저장되는 데이터를 AES256으로 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "backup_encryption" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 퍼블릭 접근 차단
# 실수로 외부 공개되지 않도록 방지
resource "aws_s3_bucket_public_access_block" "backup_public_block" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# lifecycle 정책
# 오래된 백업 파일은 저렴한 스토리지 클래스로 이동하고
# 1년 뒤 자동 삭제되도록 설정
resource "aws_s3_bucket_lifecycle_configuration" "backup_lifecycle" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "backup-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # 30일 후 Standard-IA로 전환
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # 90일 후 Glacier로 전환
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # 365일 후 자동 삭제
    expiration {
      days = 365
    }
  }
}
