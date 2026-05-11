provider "aws" {
  region = "eu-central-1"
}

# =========================
# AMI
# =========================

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# =========================
# SSH KEY
# =========================

resource "aws_key_pair" "deployer" {
  key_name   = "homepage-key"
  public_key = file("C:/Users/ros/.ssh/id_ed25519.pub")
}

# =========================
# SECURITY GROUP
# =========================

resource "aws_security_group" "web_sg" {
  name        = "homepage-sg"
  description = "Allow HTTP HTTPS SSH"

  ingress {
    description = "HTTP"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"

    from_port = 443
    to_port   = 443
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =========================
# EC2
# =========================

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  key_name = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  user_data = <<-EOF
              #!/bin/bash

              yum update -y

              # Docker
              amazon-linux-extras install docker -y
              service docker start
              systemctl enable docker

              usermod -aG docker ec2-user

              # Docker Compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

              chmod +x /usr/local/bin/docker-compose

              # App dir
              mkdir -p /home/ec2-user/app

              cd /home/ec2-user/app

              # docker-compose.yml
              cat > docker-compose.yml << 'EOL'
              version: '3.8'

              services:
                app:
                  image: rstarostsenko/go-aws-home:latest
                  restart: always

                caddy:
                  image: caddy:latest
                  restart: always

                  ports:
                    - "80:80"
                    - "443:443"

                  volumes:
                    - ./Caddyfile:/etc/caddy/Caddyfile
                    - caddy_data:/data
                    - caddy_config:/config

              volumes:
                caddy_data:
                caddy_config:
              EOL

              # Caddyfile
              cat > Caddyfile << 'EOL'
              :80 {
                  reverse_proxy app:8080
              }
              EOL

              # Start
              docker-compose up -d

              EOF

  tags = {
    Name = "GoHomePage"
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
  value = aws_eip.app_ip.public_ip
}
