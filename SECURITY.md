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
- **Single administrative account** — `root@'%'` was dropped on 15 August 2026.
  It accepted connections from any host on the Docker network with full
  privileges, and had no remaining use once the healthcheck stopped
  authenticating. Root now authenticates through the Unix socket only, so a
  compromised application container has no root account to attack over TCP.

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
- **File-based database secrets** — `taskflow-db` receives its passwords through
  Docker Compose secrets, mounted read-only at `/run/secrets/`, rather than as
  inline environment variables. Docker records `environment` verbatim in
  `Config.Env`, where `docker inspect` exposes it to anyone able to query the
  daemon, permanently and regardless of file permissions. The source files live
  in `/home/mehdi/secrets/` at mode `600`, outside the Git working copy.
- **Credential-free healthcheck** — The `taskflow-db` healthcheck runs
  `mysqladmin ping -h 127.0.0.1` with no credentials. `mysqladmin` exits 0 as
  soon as the server answers, even on access denied, and exits 1 when nothing
  listens, so authentication adds nothing to the liveness signal. Passing the
  root password as an argument, as an earlier version did, made it permanently
  visible in the container process table and in `docker inspect`.

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
- Database passwords are 40-character random alphanumeric strings, generated in a
  password manager. Special characters are excluded on purpose: they carry meaning
  in the shell, in `.env` and in SQL, and produce failures that point nowhere near
  their cause
- Database credentials are rotated on exposure, on sharing, or on schedule. The
  procedure is in
  [`docs/04-securite/DATABASE_CREDENTIAL_ROTATION.md`](docs/04-securite/DATABASE_CREDENTIAL_ROTATION.md)
- No credential is ever passed as a command-line argument. Process arguments are
  world-readable in `/proc` for the lifetime of the process
- GitHub Container Registry token has minimal scope (`read:packages`, `write:packages`)
- The backup script reads its credentials from the same `.env` file at `600`,
  and its systemd unit runs as `mehdi` rather than root, so that file permission
  remains a real control rather than a formality
- The ntfy topic used for backup alerts is treated as a secret and stored in
  `.env`: the public ntfy service has no authentication, so anyone knowing the
  topic name can read and post to it

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

### Backup Coverage

Two mechanisms cover different failures, and neither replaces the other:

- **Hetzner automated snapshots**, daily, image the whole machine. They recover
  from the loss of the server or its disk, but restore everything at once and
  cannot bring back a single table.
- **Logical dumps**, daily at 03:00 UTC, produced by `scripts/backup-db.sh`.
  They recover from logical damage — a bad migration, an accidental deletion —
  at table granularity, and can be inspected and partially replayed.

The logical dumps are stored on the VPS disk itself, so on their own they would
not survive its loss. Copying them off-site was considered and deliberately
declined on 15 August 2026: the snapshots already cover that failure mode, and
the recurring cost was not justified for a portfolio project. See issue #17.

Recovery point objective: 24 hours. Restore procedure:
[`docs/04-securite/DATABASE_RESTORE.md`](docs/04-securite/DATABASE_RESTORE.md),
verified against a throwaway container on 15 August 2026.

### In-Memory Rate Limiting

Rate limiting is handled at the application level using Bucket4j with in-memory
storage. A server restart resets all counters. See
[taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
for details.

### Application Database Credential

`taskflow-api` still receives `DB_PASSWORD` as a plain environment variable, so
it remains readable in `docker inspect taskflow-api`. Unlike the MySQL image,
Spring Boot reads its configuration at every start rather than once at
initialisation, so moving it to a file requires changing the application's
configuration rather than the Compose file. That work belongs to the
`taskflow-api` repository and is tracked there.

The exposure is limited: reading it requires access to the Docker daemon, which
already implies root-equivalent privileges on the host. It is recorded here
because a partial fix that is not documented as partial reads as a complete one.

---

## Planned Improvements

- [ ] Watchtower — automated container image updates
- [ ] Centralized log management

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