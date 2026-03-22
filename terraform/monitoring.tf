# ----------------------------------------
# monitoring.tf
# Monitoring EC2 (Prometheus + Grafana + Tailscale)
# user_data 제거 → Ansible setup-monitoring.yml로 이동
# ----------------------------------------

resource "aws_instance" "monitoring" {
  ami           = data.aws_ami.ubuntu.id  # providers.tf에서 정의한 AMI
  instance_type = var.monitoring_instance_type  # t3.micro

  # public3 (AZ-c) 전용
  # public1, public2는 Worker Node 전용이라 분리
  subnet_id = aws_subnet.public3.id

  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name

  # Tailscale Subnet Router로 동작하기 위해 필요
  # EC2 기본값은 자신의 IP로 오는 트래픽만 허용
  # false로 설정하면 DMS → 100.64.x.x 같은 경유 트래픽도 처리 가능
  source_dest_check = false


  tags = {
    Name    = "${var.project_name}-monitoring"
    Project = var.project_name
    Role    = "monitoring"
  }
}

# EC2는 IAM Role 직접 연결 불가
# Instance Profile을 통해 IAM Role 연결
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-monitoring-profile"
  role = aws_iam_role.monitoring.name  # iam.tf 참조
}