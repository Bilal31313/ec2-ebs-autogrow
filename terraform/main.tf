terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -------- IAM role (least privilege for volume modify) ----------
resource "aws_iam_role" "autogrow_role" {
  name = "ebs-autogrow-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "autogrow_policy" {
  name = "ebs-autogrow-inline"
  role = aws_iam_role.autogrow_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:ModifyVolume"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "autogrow_profile" {
  name = "ebs-autogrow-profile"
  role = aws_iam_role.autogrow_role.name
}

# -------- Security group (allow SSH + all egress) ---------------
resource "aws_security_group" "ec2" {
  name        = "ebs-autogrow-sg"
  description = "SSH in, allow all egress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_vpc" "default" {
  default = true
}

# ── pick the first default subnet in the VPC ──────────────────────
data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  default_subnet_id = data.aws_subnets.default.ids[0]
}

# -------- EC2 instance with user_data ---------------------------
resource "aws_instance" "autogrow_host" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = local.default_subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.autogrow_profile.name
  key_name               = var.key_pair_name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  user_data = <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y unzip curl cloud-guest-utils

# install AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# copy script from user-data
cat > /usr/local/bin/auto_grow.sh <<'EOS'
$(cat ../files/auto_grow.sh | sed "s/'/'\"'\"'/g")
EOS
chmod +x /usr/local/bin/auto_grow.sh

# cron every 10 min as root
echo "*/10 * * * * /usr/local/bin/auto_grow.sh" | crontab -
EOF

  tags = {
    Name = "ebs-autogrow-host"
  }
}

output "instance_public_ip" {
  value = aws_instance.autogrow_host.public_ip
}
