provider "aws" {
  region = var.aws_region
}

# =========================
# VARIABLES
# =========================
variable "aws_region" {
  type        = string
  description = "AWS target region"
}

variable "domain_name" {
  type        = string
  description = "Target domain name for Caddy SSL"
}

variable "email_user" {
  type        = string
  description = "Username part for email obfuscation"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to local SSH public key file"
}

variable "grafana_password" {
  type        = string
  description = "Admin password for Grafana dashboard"
  sensitive   = true
}

variable "prometheus_password_hash" {
  type        = string
  description = "Bcrypt hash for Prometheus basic_auth (caddy hash-password)"
  sensitive   = true
}

variable "docker_image_tag" {
  type        = string
  description = "Docker image tag to deploy (use git SHA for reproducibility)"
  default     = "latest"
}

# Динамическое получение домашнего IP для ограничения SSH
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

# =========================
# AMI
# =========================
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# =========================
# SSH KEY
# =========================
resource "aws_key_pair" "deployer" {
  key_name   = "homepage-sshkey"
  public_key = file(var.ssh_public_key_path)
}

# =========================
# SECURITY GROUP
# =========================
resource "aws_security_group" "web_sg" {
  name        = "homepage-sg"
  description = "Allow HTTP, HTTPS, and SSH from deployer IP only"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from deployer IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${trimspace(data.http.my_public_ip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =========================
# EC2 INSTANCE
# =========================
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # user_data теперь только устанавливает Docker и запускает стек.
  # Конфигурационные файлы деплоятся отдельно через file provisioner ниже —
  # это устраняет дублирование и позволяет обновлять конфиги без пересоздания EC2.
  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              yum update -y

              # Docker
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              # Docker Compose v2 (плагин)
              mkdir -p /usr/local/lib/docker/cli-plugins
              curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose
              chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

              # Директории для конфигов (файлы придут через provisioner)
              mkdir -p /home/ec2-user/app/prometheus
              chown -R ec2-user:ec2-user /home/ec2-user/app
              EOF

  tags = {
    Name = "GoHomePage"
  }

  # Provisioner'ы выполняются после создания инстанса по SSH.
  # Они копируют конфигурационные файлы прямо из репозитория — без дублирования кода.
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("~/.ssh/id_ed25519")
    host        = aws_eip.app_ip.public_ip
  }

  # 1. .env с секретами (генерируется из переменных Terraform)
  provisioner "file" {
    content = templatefile("${path.module}/.env.tpl", {
      email_user       = var.email_user
      domain_name      = var.domain_name
      grafana_password = var.grafana_password
      image_tag        = var.docker_image_tag
    })
    destination = "/home/ec2-user/app/.env"
  }

  # 2. docker-compose.yml из репозитория (единственный источник правды)
  provisioner "file" {
    source      = "${path.module}/docker-compose.yml"
    destination = "/home/ec2-user/app/docker-compose.yml"
  }

  # 3. Caddyfile — генерируется из шаблона (подставляем domain и hash)
  provisioner "file" {
    content = templatefile("${path.module}/Caddyfile.tpl", {
      domain_name              = var.domain_name
      prometheus_password_hash = var.prometheus_password_hash
    })
    destination = "/home/ec2-user/app/Caddyfile"
  }

  # 4. prometheus.yml из репозитория
  provisioner "file" {
    source      = "${path.module}/prometheus/prometheus.yml"
    destination = "/home/ec2-user/app/prometheus/prometheus.yml"
  }

  # 5. Запускаем стек
  provisioner "remote-exec" {
    inline = [
      "cd /home/ec2-user/app",
      "docker compose pull",
      "docker compose up -d",
    ]
  }
}

# =========================
# ELASTIC IP
# =========================
resource "aws_eip" "app_ip" {
  instance = aws_instance.app_server.id
  tags = {
    Name = "homepage-ip"
  }
}

# =========================
# OUTPUT
# =========================
output "public_ip" {
  value       = aws_eip.app_ip.public_ip
  description = "Elastic IP адрес EC2 инстанса"
}
