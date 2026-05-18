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

variable "ssh_private_key_path" {
  type        = string
  description = "Path to local SSH private key file used for provisioning"
  default     = "~/.ssh/id_ed25519"
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

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # Docker
              yum update -y
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/bin/docker-compose
              chmod +x /usr/bin/docker-compose
              touch /tmp/user_data_done
              EOF
  tags = {
    Name = "GoHomePage"
  }
}

# =========================
# ELASTIC IP & ASSOCIATION
# =========================
resource "aws_eip" "app_ip" {
  domain = "vpc"
  tags = {
    Name = "homepage-ip"
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.app_server.id
  allocation_id = aws_eip.app_ip.id
}

resource "null_resource" "deploy" {
  depends_on = [aws_eip_association.eip_assoc]

  # Повторный деплой произойдёт если изменится тег образа, домен или инстанс
  triggers = {
    image_tag   = var.docker_image_tag
    domain_name = var.domain_name
    instance_id = aws_instance.app_server.id
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_eip.app_ip.public_ip
    timeout     = "10m"
  }

  # ШАГ 0: Ждём завершения user_data и появления docker-compose
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for user_data to finish...'",
      "while [ ! -f /tmp/user_data_done ]; do sleep 10; echo 'Still waiting for user_data...'; done",
      "echo 'Waiting for docker-compose binary...'",
      "while [ ! -f /usr/bin/docker-compose ]; do sleep 5; done",
      "echo 'All ready. Creating directories...'",
      "mkdir -p /home/ec2-user/app/prometheus",
      "chown -R ec2-user:ec2-user /home/ec2-user/app",
    ]
  }

  # 1. .env с секретами (генерируется из Terraform переменных)
  provisioner "file" {
    content = templatefile("${path.module}/.env.tpl", {
      email_user       = var.email_user
      domain_name      = var.domain_name
      grafana_password = var.grafana_password
      image_tag        = var.docker_image_tag
    })
    destination = "/home/ec2-user/app/.env"
  }

  # 2. docker-compose.yml
  provisioner "file" {
    source      = "${path.module}/../docker-compose.yml"
    destination = "/home/ec2-user/app/docker-compose.yml"
  }

  # 3. Caddyfile из шаблона (domain + bcrypt hash)
  provisioner "file" {
    content = templatefile("${path.module}/Caddyfile.tpl", {
      domain_name              = var.domain_name
      prometheus_password_hash = replace(var.prometheus_password_hash, "$", "$$")
    })
    destination = "/home/ec2-user/app/Caddyfile"
  }

  # 4. prometheus.yml
  provisioner "file" {
    source      = "${path.module}/../prometheus/prometheus.yml"
    destination = "/home/ec2-user/app/prometheus/prometheus.yml"
  }

  # 5. Запуск стека
  provisioner "remote-exec" {
    inline = [
      "cd /home/ec2-user/app",
      "sudo docker-compose pull",
      "sudo docker-compose up -d",
      "echo 'Deployment completed successfully!'",
    ]
  }
}

# =========================
# OUTPUT
# =========================
output "public_ip" {
  value       = aws_eip.app_ip.public_ip
  description = "Elastic IP адрес EC2 инстанса"
}
