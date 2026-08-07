# Security Policy

> 🇫🇷 [Lire en français](SECURITY.fr.md)

## Overview

This document describes the infrastructure security measures implemented for the
TaskFlow production deployment on Hetzner VPS.

TaskFlow is a portfolio project demonstrating modern DevOps and security practices
with Docker, Nginx, Let's Encrypt and Ubuntu 24.04.

---

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |

---

## Security Measures

### Server Hardening

- **Non-root user** — The application runs under a dedicated `mehdi` user with sudo
  privileges. Direct root login is disabled.
- **SSH key authentication only** — Password authentication is disabled in
  `/etc/ssh/sshd_config`. Only Ed25519 public key authentication is accepted.
- **UFW firewall** — Only ports 22 (SSH), 80 (HTTP) and 443 (HTTPS) are open.
  All other inbound traffic is blocked by default.
- **Fail2ban** — Automatically bans IPs after 5 failed SSH attempts within 10 minutes.
  Ban duration: 1 hour.

### Docker Security

- **Non-root containers** — The `taskflow-api` container runs as a dedicated
  non-root `taskflow` user. The `taskflow-ui` container runs as `nginx`.
- **Internal network** — All inter-container communication uses a private Docker
  bridge network (`taskflow-network`). MySQL is not exposed to the host network.
- **Loopback-only port publishing** — Container ports are published on `127.0.0.1`
  only. Nginx, running on the host, proxies to them over the loopback interface;
  they are not reachable from outside the VPS.
- **Private registry** — Docker images are stored privately on GitHub Container
  Registry (ghcr.io) and require authentication to pull.
- **Read-only secrets** — The `.env` file containing production secrets has
  permissions `600` (owner read/write only).

### Transport Security

- **HTTPS enforced** — Nginx redirects all HTTP traffic to HTTPS via a permanent
  `301` redirect.
- **Let's Encrypt SSL** — TLS certificates are issued by Let's Encrypt and renewed
  automatically via Certbot's systemd timer.
- **HSTS** — `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  enforced by the API on all responses.

### Nginx Security

- **Reverse proxy** — Nginx acts as the sole entry point. Backend services are
  not directly accessible from the internet.
- **`server_tokens off`** — Nginx version is hidden from response headers.
- **robots.txt** — Both `taskflow.mehdi-rochereau.dev` and
  `api.taskflow.mehdi-rochereau.dev` return `Disallow: /` to prevent search
  engine indexing.

### Secret Management

- `.env` is excluded from version control via `.gitignore`
- `.env` contains no default values for production secrets
- JWT secret is generated with `openssl rand -hex 64` — 512-bit entropy
- Database passwords are generated with `openssl rand -hex 32` — 256-bit entropy
- GitHub Container Registry token has minimal scope (`read:packages`, `write:packages`)

### Application Security

All application-level security is documented in the respective repositories:

- [taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
  — JWT, HttpOnly cookies, rate limiting, input sanitization, audit logging
- [taskflow-ui/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-ui/blob/main/SECURITY.md)
  — XSS prevention, CSRF protection, route guards, silent refresh

---

## Security Principles Applied

| Principle | Implementation |
|-----------|----------------|
| **Defense in Depth** | UFW + Fail2ban + SSH keys + Docker network isolation + Nginx reverse proxy |
| **Least Privilege** | Non-root OS user, non-root containers, scoped GitHub token, internal MySQL |
| **Fail Secure** | Root login disabled, password auth disabled, all ports closed by default |
| **Secret Hygiene** | `.env` at `600`, excluded from git, no defaults for production secrets |
| **Encryption in Transit** | HTTPS enforced, HSTS enabled, Let's Encrypt auto-renewal |

---

## Known Limitations

### Single Server Architecture

The current deployment runs all services on a single VPS. This means:
- No high availability — a server failure takes down all services
- No horizontal scaling — CPU and memory are shared between API, UI and database
- Backups rely on Hetzner's automated snapshot feature (daily)

A production-grade deployment would use separate database servers, load balancers
and a container orchestration platform such as Kubernetes.

### In-Memory Rate Limiting

Rate limiting is handled at the application level using Bucket4j with in-memory
storage. A server restart resets all counters. See
[taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
for details.

---

## Planned Improvements

- [ ] GitHub Actions CI/CD — automated build, push and deploy pipeline
- [ ] Watchtower — automated container image updates
- [ ] Centralized log management
- [ ] Database backup automation

---

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it
responsibly by contacting:

**Email:** mehdi.rochereau.dev@gmail.com

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact

This is a portfolio project and is not intended for production use with real user data.
Response time may vary.

---

## Related

- [taskflow-api](https://github.com/mehdi-rochereau/taskflow-api) — Spring Boot REST API
- [taskflow-ui](https://github.com/mehdi-rochereau/taskflow-ui) — Angular frontend
- [taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md) — API security policy
- [taskflow-ui/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-ui/blob/main/SECURITY.md) — Frontend security policy