# High-Availability DevOps Homepage & Infrastructure Monitoring Stack

Production-ready, highly efficient, and containerized portfolio infrastructure built with **Go**, automated via **GitHub Actions**, provisioned by **Terraform**, and continuously monitored using **Prometheus & Grafana**.

## 🚀 Key Features & Architecture

- **Go Backend**: High-performance, lightweight web server using `html/template` with robust error handling and isolated internal metrics instrumentation.
- **Automated Anti-Spam (Obfuscation)**: Dynamic runtime HTML injection of critical contact data (email) driven by template context variables to block aggressive crawler bots.
- **Caddy Edge Proxy**: Orchestrates zero-maintenance, automated SSL/TLS termination via Let's Encrypt / ZeroSSL, serving as a secure entry point for multiple subdomains.
- **Enterprise-Grade Security Headers**: Full protection against XSS, Clickjacking, and MIME-sniffing via optimized HTTP headers (`CSP`, `HSTS`, `X-Frame-Options`) configured at the proxy layer.
- **Robust Observability Matrix**: Full four-tier metric scraping system collecting application, system, and hardware indicators.
- **Infrastructure as Code (IaC)**: Dynamic AWS ecosystem provisioning via Terraform with Automated Security Groups adjustments based on remote location validation.

---

## 🏗️ System Architecture

```text
               ┌───────────────────────────────────────────────┐
               │              Public Internet                  │
               └──────────────────────┬────────────────────────┘
                                      │
                                      ▼ [Ports 80 / 443]
                       ┌─────────────────────────────┐
                       │      Caddy Edge Proxy       │
                       └──────────────┬──────────────┘
                                      │
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼ [Port 8080]                  ▼ [Port 3000]                  ▼ [Port 9090]
┌──────────────┐               ┌──────────────┐               ┌──────────────┐
│  Go Web App  │               │   Grafana    │               │  Prometheus  │
└──────┬───────┘               └──────▲───────┘               └──────▲───────┘
       │                              │                              │
       │ [Port 8081]                  └──────────────┬───────────────┘
       └─────────────────────────────────────────────┼───────────────┐
                                                     │               │
                                              Scrapes│               │Scrapes
                                                     │               │
                                             ┌───────┴──────┐ ┌──────┴──────┐
                                             │Node Exporter │ │  cAdvisor   │
                                             └──────────────┘ └─────────────┘
```

---

## 📊 Observability Matrix Setup

The project includes an advanced telemetry gathering setup divided into four major metrics pipelines:

1. **Go Application Layer (`app:8081`)**: Tracks real-time raw HTTP latency, active routines, memory heap allocations, and Garbage Collection (GC) pauses via the official Prometheus Go client runtime.
2. **Container Telemetry (`cadvisor:8080`)**: Collects continuous aggregate statistics regarding CPU throttling, memory limits, and IO limits across all running Docker containers.
3. **OS & Hardware Matrix (`localhost:9100`)**: Deployed using `network_mode: host` to directly monitor AWS EC2 instance metrics (Disk I/O, available RAM, CPU utilization).
4. **Self-Monitoring (`localhost:9090`)**: Scrapes Prometheus internally to trace time-series storage health and prevent out-of-memory crashes on the `t3.micro` instance.

---

## ⚙️ Configuration Files Structure

### 1. Docker Compose Configuration (`docker-compose.yml`)
Services are isolated within a private bridge network. Caddy utilizes persistent Docker volumes to maintain SSL state and prevent API rate-limiting issues.
- **`app`**: Injects localized configurations from a secure `.env` mapping.
- **`caddy`**: Binds to ports `80/443` and handles request dispatching.
- **`prometheus`/`grafana`**: Isolated with persistent volumes ensuring dashboard and logging preservation during redeployments.

### 2. Caddy Routing Configuration (`Caddyfile`)
Includes structural optimization via modular Caddy snippets:
- `starostsenko.xyz` & `www.starostsenko.xyz`: Forwards requests to the main application with strict `CSP` and `HSTS` enforcement.
- `grafana.starostsenko.xyz`: Securely routes control plane monitoring tools without breaking application-specific scripts.
- `prometheus.starostsenko.xyz`: Protected behind cryptographic `basic_auth` server layers generated dynamically.

---

## 🛠️ Infrastructure and CI/CD Automation

### Infrastructure Provisioning (`main.tf`)
The AWS blueprint leverages infrastructure-as-code paradigms to ensure zero drift:
- **Dynamic Security Groups**: The Terraform engine dynamically queries `://amazonaws.com` at runtime to automatically open port 22 (SSH) *exclusively* for your current dynamic home IP address (`/32` block).
- **Elastic IP (EIP)**: Implemented to guarantee a static anchor pointing to AWS EC2, keeping public DNS propagation and SSL automation highly stable.

### Continuous Integration Workflow (`.github/workflows/`)
Automated multi-architecture builds triggered upon merges to the master repository branch:
1. Validates local Go code standards and formatting.
2. Performs automated login against a secure external container registry.
3. Assembles lightweight layers via Buildx and ships dual-tagged images (`latest` and `${{ github.sha }}`).

---

## 🏃 Local Development and Deployment

1. **Clone the code**:
   ```bash
   git clone https://github.com
   cd go-aws-home
   ```

2. **Configure your localized secrets**:
   Create a local root `.env` file mapping required attributes:
   ```env
   EMAIL_USER=info
   EMAIL_DOMAIN=starostsenko.xyz
   SERVER_PORT=8080
   GRAFANA_PASSWORD=your_secure_password
   ```

3. **Spin up the stack**:
   ```bash
   docker compose up -d
   ```
   Access your application at `http://localhost:8080` and internal telemetry endpoints via `http://localhost:8081/metrics`.
