# TaskFlow Deploy

> 🇫🇷 [Version française](README.fr.md)

Production deployment configuration for the TaskFlow application — Docker Compose stack, Nginx reverse proxy, SSL certificates and deployment scripts.

[![Docker](https://img.shields.io/badge/Docker-26-2496ED?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Nginx](https://img.shields.io/badge/Nginx-1.24-009639?style=flat&logo=nginx&logoColor=white)](https://nginx.org/)
[![Let's Encrypt](https://img.shields.io/badge/SSL-Let's%20Encrypt-003A70?style=flat&logo=letsencrypt&logoColor=white)](https://letsencrypt.org/)
[![Hetzner](https://img.shields.io/badge/VPS-Hetzner-D50C2D?style=flat&logo=hetzner&logoColor=white)](https://www.hetzner.com/)

---

## Overview

This repository contains the production infrastructure configuration for TaskFlow.
It orchestrates three Docker containers — MySQL, Spring Boot API and Angular UI —
behind an Nginx reverse proxy with Let's Encrypt SSL certificates on a Hetzner VPS.

🌐 **Live:** [taskflow.mehdi-rochereau.dev](https://taskflow.mehdi-rochereau.dev)
📖 **API Docs:** [api.taskflow.mehdi-rochereau.dev/swagger-ui/index.html](https://api.taskflow.mehdi-rochereau.dev/swagger-ui/index.html)

---

## Architecture

```
Internet
    │
    ▼
taskflow.mehdi-rochereau.dev          → TaskFlow UI
api.taskflow.mehdi-rochereau.dev      → TaskFlow API
    │
    ▼
VPS Hetzner CPX22 (Ubuntu 24.04)
    │
    ├── Nginx (reverse proxy — SSL termination, routing)
    │       ├── → taskflow-ui  (port 4000)
    │       └── → taskflow-api (port 8082)
    │
    └── Docker Compose
            ├── taskflow-api  (Spring Boot 3.5 / Java 21)
            ├── taskflow-ui   (Angular 21 + Nginx)
            └── taskflow-db   (MySQL 8.0)
```

---

## Repository Structure

```
taskflow-deploy/
├── docker-compose.yml     # Docker Compose stack definition
├── .env.example           # Environment variables template
├── .gitignore             # Excludes .env and secrets
├── scripts/
│   ├── deploy.sh          # Production deployment script
│   └── .gitattributes     # Line ending configuration
└── README.md
```

---

## Infrastructure

| Component | Details |
|-----------|---------|
| VPS | Hetzner CPX22 — 2 vCPU, 4 GB RAM, 80 GB SSD |
| OS | Ubuntu 24.04 LTS |
| Reverse Proxy | Nginx 1.24 |
| SSL | Let's Encrypt — auto-renewed via Certbot |
| Container Runtime | Docker 26 + Docker Compose v2 |
| Registry | GitHub Container Registry (ghcr.io) |

---

## Services

| Service | Image | Port | Description |
|---------|-------|------|-------------|
| `taskflow-db` | `mysql:8.0` | — | MySQL database (internal only) |
| `taskflow-api` | `ghcr.io/mehdi-rochereau/taskflow-api:latest` | `8082` | Spring Boot REST API |
| `taskflow-ui` | `ghcr.io/mehdi-rochereau/taskflow-ui:latest` | `4000` | Angular frontend |

---

## Prerequisites

- VPS running Ubuntu 24.04
- Docker and Docker Compose installed
- Nginx and Certbot installed
- DNS records pointing to the VPS IP
- GitHub Container Registry access configured

---

## Initial Server Setup

**1. Install Docker**

```bash
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```

**2. Install Nginx and Certbot**

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

**3. Clone this repository**

```bash
sudo mkdir -p /opt/taskflow
sudo chown $USER:$USER /opt/taskflow
cd /opt/taskflow
git clone https://github.com/mehdi-rochereau/taskflow-deploy.git .
```

**4. Configure environment variables**

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

**5. Authenticate with GitHub Container Registry**

```bash
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

**6. Configure Nginx**

```bash
sudo nano /etc/nginx/sites-available/taskflow
sudo nano /etc/nginx/sites-available/api-taskflow
sudo ln -s /etc/nginx/sites-available/taskflow /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/api-taskflow /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

**7. Generate SSL certificates**

```bash
sudo certbot --nginx -d taskflow.mehdi-rochereau.dev -d api.taskflow.mehdi-rochereau.dev
```

---

## Deployment

**Pull and start the stack**

```bash
docker compose pull
docker compose up -d
```

**Using the deployment script**

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

The script automatically pulls the latest images, restarts the stack and verifies the API health check.

**Check service status**

```bash
docker compose ps
docker compose logs taskflow-api --tail=50
```

---

## Environment Variables

Copy `.env.example` to `.env` and fill in real values.

| Variable | Description |
|----------|-------------|
| `MYSQL_ROOT_PASSWORD` | MySQL root password — internal use only |
| `DB_HOST` | Database host — `taskflow-db` (Docker service name) |
| `DB_PORT` | Database port — `3306` |
| `DB_NAME` | Database name |
| `DB_USERNAME` | Application database user |
| `DB_PASSWORD` | Application database password |
| `JWT_SECRET` | HMAC-SHA512 signing key — minimum 32 characters |
| `JWT_EXPIRATION` | JWT expiry in milliseconds — default `900000` (15 min) |
| `COOKIE_SECURE` | Enable `Secure` flag on cookies — `true` in production |
| `REFRESH_TOKEN_EXPIRATION_DAYS` | Refresh token validity — default `7` days |
| `CORS_ALLOWED_ORIGINS` | Allowed CORS origin — `https://taskflow.mehdi-rochereau.dev` |

Generate a secure JWT secret:

```bash
openssl rand -hex 64
```

---

## Security

- `.env` is excluded from version control via `.gitignore`
- `.env` permissions are restricted to `600` (owner read/write only)
- Docker images are private on GitHub Container Registry
- MySQL port is not exposed outside the Docker network
- All traffic is encrypted via HTTPS (Let's Encrypt)
- Nginx enforces HTTP → HTTPS redirection

For application-level security details, see:
- [taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
- [taskflow-ui/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-ui/blob/main/SECURITY.md)

---

## Planned Improvements

- [ ] GitHub Actions CI/CD — automatic build, push and deploy on `main` push
- [ ] Watchtower — automatic container updates
- [ ] Log rotation and centralized logging

---
 
## Project Management & Documentation
 
The three TaskFlow repositories are managed from a single
[GitHub Project](https://github.com/users/mehdi-rochereau/projects/4):
issue first, branch created from the issue, pull request, squash merge, with a
five-status workflow (Backlog → In Progress → In Review → Verifying → Done).
 
Cross-repository documentation lives in [`docs/`](docs/), including the full
project management manual:
[`docs/02-gestion-de-projet/PROJECT_MANAGEMENT.md`](docs/02-gestion-de-projet/PROJECT_MANAGEMENT.md).

---

## Ecosystem

| Repository | Description |
|------------|-------------|
| [taskflow-deploy](https://github.com/mehdi-rochereau/taskflow-deploy) | Deployment configuration (this repo) |
| [taskflow-api](https://github.com/mehdi-rochereau/taskflow-api) | Spring Boot REST API |
| [taskflow-ui](https://github.com/mehdi-rochereau/taskflow-ui) | Angular frontend |