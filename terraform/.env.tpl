# Docker — docker-compose.yml
DOCKER_REGISTRY=rstarostsenko
IMAGE_NAME=go-aws-home
IMAGE_TAG=${image_tag}
DOMAIN_NAME=${domain_name}

# Go
EMAIL_USER=${email_user}
EMAIL_DOMAIN=${domain_name}
SERVER_PORT=8080

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=${grafana_password}
