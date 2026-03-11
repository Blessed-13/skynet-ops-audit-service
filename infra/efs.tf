# ── EFS File System ───────────────────────────────────────────────────────────
resource "aws_efs_file_system" "data" {
  creation_token   = "${var.app_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"       # cheapest option for low traffic
  encrypted        = true             # encrypt data at rest

  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS" # move unused files to cheaper storage
  }

  tags = { Name = "${var.app_name}-efs" }
}

# ── Security Group for EFS ────────────────────────────────────────────────────
resource "aws_security_group" "efs" {
  name        = "${var.app_name}-efs-sg"
  description = "Allow NFS from ECS tasks only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 2049 # NFS port
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id] # only ECS can access EFS
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-efs-sg" }
}

# ── EFS Mount Targets (one per subnet) ───────────────────────────────────────
resource "aws_efs_mount_target" "a" {
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = aws_subnet.public_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = aws_subnet.public_b.id
  security_groups = [aws_security_group.efs.id]
}

# ── EFS Access Point ──────────────────────────────────────────────────────────
resource "aws_efs_access_point" "data" {
  file_system_id = aws_efs_file_system.data.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = { Name = "${var.app_name}-efs-ap" }
}
