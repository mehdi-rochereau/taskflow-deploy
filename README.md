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
            └── taskflow-db   (MySQL 8.4)
```

---

## Repository Structure

```
taskflow-deploy/
├── docker-compose.yml     # Docker Compose stack definition
├── .env.example           # Environment variables template
├── .gitignore             # Excludes .env and secrets
├── README.md              # This file
├── README.fr.md           # French version
├── SECURITY.md            # Infrastructure security policy
├── SECURITY.fr.md         # French version
├── .github/               # Issue and pull request templates
├── db/
│   └── init/              # SQL executed on first volume initialisation only
├── docs/                  # Cross-repository project documentation
│   ├── README.md
│   ├── 01-expression-des-besoins/
│   ├── 02-gestion-de-projet/
│   ├── 04-securite/
│   └── images/
├── nginx/                 # Reverse proxy configuration, mirrored to /etc/nginx
│   ├── conf.d/            # Server-wide hardening, loaded into the http block
│   ├── sites-available/   # One vhost per host name, plus the catch-all
│   ├── snippets/          # Shared blocks included by the vhosts
│   ├── NGINX_CONF_CHANGES.md  # Deliberate divergences from the packaged nginx.conf
│   └── .gitattributes     # Line ending configuration
├── scripts/
│   ├── backup-db.sh       # Automated database backup
│   ├── check-nginx-sync.sh    # Compares nginx/ with what is deployed
│   ├── deploy.sh          # Production deployment script
│   └── .gitattributes     # Line ending configuration
└── systemd/
    ├── taskflow-backup.service
    ├── taskflow-backup.timer
    └── .gitattributes     # Line ending configuration
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
| `taskflow-db` | `mysql:8.4` | — | MySQL database (internal only) |
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

**5. Create the secret files**

```bash
mkdir -p /home/mehdi/secrets
chmod 700 /home/mehdi/secrets

read -rsp "MySQL root password: " P; echo
printf '%s' "$P" > /home/mehdi/secrets/mysql_root_password

read -rsp "MySQL application password: " P; echo
printf '%s' "$P" > /home/mehdi/secrets/mysql_password

openssl rand -hex 64 | tr -d '\n' > /home/mehdi/secrets/jwt_secret

chmod 600 /home/mehdi/secrets/mysql_root_password

sudo chgrp 999 /home/mehdi/secrets/mysql_password \
               /home/mehdi/secrets/jwt_secret
chmod 640 /home/mehdi/secrets/mysql_password \
          /home/mehdi/secrets/jwt_secret
unset P
```

These three files are mounted as Docker Compose secrets. They live outside
`/opt/taskflow`, which is a Git working copy of a public repository.

`mysql_password` is mounted twice, on `taskflow-db` as `mysql_password` and on
`taskflow-api` as `db.password`. It is the password of the `taskflow` account:
MySQL uses it to create the account, the API uses it to connect. There is one
file, never two, so a rotation cannot leave the two services disagreeing.

`jwt_secret` is mounted on `taskflow-api` alone, as `jwt.secret`. Both names
matter to the character: the API imports the whole directory as configuration,
so each file name becomes a property name.

`printf '%s'` rather than `echo`, and `tr -d '\n'` after `openssl`: each file is
read verbatim, and a trailing newline would become part of the value.

The permissions are not uniform, and the difference is not cosmetic. Compose
mounts a secret preserving the source file's owner and mode. `taskflow-db` reads
its two files as root before dropping to `mysql`, so mode 600 is enough there.
`taskflow-api` runs as `taskflow`, UID and GID 999, and never has root, so at
600 it finds its files and cannot read them: the API refuses to start with
`java.nio.file.AccessDeniedException` naming the file. Group 999 with mode 640
gives the container read access while the files stay owned by `mehdi`, who reads
`mysql_password` as owner for the backup script.

Group 999 is `systemd-journal` on the host, which is a coincidence of numbering
and not a decision: the same GID is `taskflow` inside the container. That group
has no members on Ubuntu, which `getent group systemd-journal` confirms, so
mode 640 grants read access to no account on the VPS.

The value 999 is declared in the production Dockerfile of `taskflow-api`, by
`groupadd -r -g 999` and `useradd -r -u 999`. A change there fails the build
rather than shifting silently, so the dependency is explicit on both sides. It
stays verifiable at any time:

```bash
docker run --rm --entrypoint id ghcr.io/mehdi-rochereau/taskflow-api:latest
```

Only the production image carries those identifiers. The local development
Dockerfile of `taskflow-api` is Alpine-based and produces `uid=100 gid=101`,
Alpine's tools counting up from 100 where Debian's `useradd -r` counts down from
999. The two have always differed. Mounting these same secret files against a
locally built image therefore yields an `AccessDeniedException` that is not a
regression, and the group has to be adjusted to that image's own GID.

`docker compose config` fails if any file is missing, so the omission is caught
before anything starts. A missing file at runtime is caught too, but later: the
API refuses to start and names the property it could not resolve.

**6. Authenticate with GitHub Container Registry**

```bash
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

**7. Configure Nginx**

The configuration lives in `nginx/` in this repository and is copied to
`/etc/nginx`. Do not edit the copies on the server: they would drift from the
repository with nothing to signal it.

```bash
sudo cp nginx/snippets/taskflow-*.conf /etc/nginx/snippets/
sudo cp nginx/conf.d/10-hardening.conf /etc/nginx/conf.d/
sudo cp nginx/sites-available/00-catch-all /etc/nginx/sites-available/
sudo cp nginx/sites-available/taskflow /etc/nginx/sites-available/
sudo cp nginx/sites-available/api-taskflow /etc/nginx/sites-available/

sudo chown root:root /etc/nginx/snippets/taskflow-*.conf \
                     /etc/nginx/conf.d/10-hardening.conf \
                     /etc/nginx/sites-available/00-catch-all \
                     /etc/nginx/sites-available/taskflow \
                     /etc/nginx/sites-available/api-taskflow

sudo chmod 644 /etc/nginx/snippets/taskflow-*.conf \
               /etc/nginx/conf.d/10-hardening.conf \
               /etc/nginx/sites-available/00-catch-all \
               /etc/nginx/sites-available/taskflow \
               /etc/nginx/sites-available/api-taskflow

sudo ln -s /etc/nginx/sites-available/00-catch-all /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/taskflow /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/api-taskflow /etc/nginx/sites-enabled/

sudo rm /etc/nginx/sites-enabled/default

sudo nginx -t && sudo systemctl reload nginx
```

Removing the `default` symlink is not optional. That file carries
`default_server` on port 80, and Nginx refuses two blocks claiming the role on
the same address and port pair: leaving it enabled fails `nginx -t` with
`a duplicate default server for 0.0.0.0:80`. The file itself stays in
`sites-available`, where the package keeps updating it.

Removing it also stops Nginx listening on IPv6, that vhost being the only one
that carried `listen [::]:80`. Neither host name has an AAAA record, so nothing
legitimate arrives that way. Adding one later means adding `listen [::]` to the
catch-all and to both vhosts, in the same change.

One change to `/etc/nginx/nginx.conf` is not covered by these files. Its
`ssl_protocols` line ships with `TLSv1 TLSv1.1 TLSv1.2 TLSv1.3`; the first two
are dead since 2021 and must be removed:

```bash
sudo sed -i 's/^\(\s*\)ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;.*/\1ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf
sudo nginx -T | grep ssl_protocols
```

That file is a dpkg conffile and is not versioned here, so this half of the
hardening lives outside Git. The `grep` is the check: the expected output
carries `TLSv1.2` and `TLSv1.3` only. Run it again after any Nginx package
upgrade.

The vhosts reference `/var/www/certbot`, created at step 8, and a certificate
that does not exist yet. Nginx will refuse to start until step 8 has run, which
is why the reload above may fail on a first installation.

**8. Generate SSL certificates**

```bash
sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
sudo chown -R root:root /var/www/certbot
sudo chmod -R 755 /var/www/certbot

sudo certbot certonly --webroot -w /var/www/certbot \
  -d taskflow.mehdi-rochereau.dev -d api.taskflow.mehdi-rochereau.dev
```

`certonly --webroot` and not `--nginx`. The nginx plugin doubles as an installer:
it edits the vhosts on every renewal to place its challenge, restores them and
rewrites the certificate lines. Versioned vhosts would drift from production with
nothing to signal it. In webroot mode Certbot writes a file into a dedicated
directory and never touches the web server configuration.

The directory is owned by `root` and world-readable. Certbot writes into it as
root; Nginx, running as `www-data`, only reads. A webroot writable by the account
serving it would let a compromise of that account publish arbitrary files.

The vhosts serve `/.well-known/acme-challenge/` over plain HTTP and redirect
everything else, which is what makes the challenge reachable. See the vhost
configuration in `nginx/`.

**9. Install the renewal hook**

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

/usr/sbin/nginx -t
/bin/systemctl reload nginx
EOF

sudo chmod 700 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo certbot renew --dry-run --run-deploy-hooks
```

Required, and easy to forget. Without the nginx installer nothing reloads the web
server after a renewal, and Nginx keeps serving from memory the certificate it
loaded at startup. The renewal would succeed on disk while production served an
expired certificate, with nothing to signal it until browsers refused the site.

Deploy hooks run only when a certificate was actually renewed, so this costs
nothing on the twice-daily timer. `nginx -t` guards the reload: a configuration
broken by an unrelated edit must not be loaded by an automated job.

`--run-deploy-hooks` is what makes the dry run exercise the hook. Without it a
dry run skips deploy hooks entirely, since no certificate is renewed, and would
validate nothing. `nginx -t` writes to standard error even on success, so Certbot
reports `Hook 'deploy-hook' ran with error output` on a run that succeeded. The
exit code is what matters.

---

## Deployment

**Pull and start the stack**

```bash
docker compose pull
docker compose up -d
```

**Using the deployment script**

`scripts/deploy.sh` deploys one application service at a time. It is the entry
point called by the CD pipelines, and can also be run by hand.

```bash
./scripts/deploy.sh taskflow-api
./scripts/deploy.sh taskflow-ui
```

The service name is mandatory: an invocation with no argument is refused rather
than treated as a request to redeploy everything. `taskflow-db` is not an
accepted value, is never pulled, and is never recreated: `up -d` carries
`--no-deps`, without which Compose would bring up the services declared in
`depends_on` and recreate any whose configuration has drifted from the compose
file.

Because of that, a change to the `taskflow-db` service in the compose file will
never reach production through a deployment. It has to be applied by hand,
knowingly, with a manual dump taken first.

The script refuses to deploy when `taskflow-db` is not `healthy`. `--no-deps`
removes the `service_healthy` condition Compose would otherwise wait on, so the
check is made here instead. In rollback mode the state is reported but not
enforced: a recovery path should have as few conditions as possible.

Before doing anything the script checks that `docker-compose.yml`, `.env` and
`db/init/01-healthcheck-account.sql` are present, and aborts if any is missing.
Compose silently creates a missing bind mount source as an empty directory, so a
deployment from an incomplete working copy would leave the database without its
healthcheck account on the next rebuild.

Rolling back the last deployment of a service:

```bash
./scripts/deploy.sh taskflow-api --rollback
```

The script performs no `git` operation. Updating this working copy is the
caller's responsibility, before the script is invoked:

```bash
cd /opt/taskflow && git pull --ff-only
```

Health checking is the caller's responsibility too: it queries the public URL
through Nginx and TLS, which the script cannot observe from inside the VPS.
Deploying a service recreates its container, which interrupts it for a few
seconds.

**Check service status**

```bash
docker compose ps
docker compose logs taskflow-api --tail=50
```

**Updating the Nginx configuration**

Nginx does not read this repository. A change to a file under `nginx/` reaches
production only when it is copied to `/etc/nginx` by hand, after the working
copy has been updated:

```bash
cd /opt/taskflow
git pull --ff-only

sudo cp nginx/snippets/taskflow-*.conf /etc/nginx/snippets/
sudo cp nginx/conf.d/10-hardening.conf /etc/nginx/conf.d/
sudo cp nginx/sites-available/00-catch-all /etc/nginx/sites-available/
sudo cp nginx/sites-available/taskflow /etc/nginx/sites-available/
sudo cp nginx/sites-available/api-taskflow /etc/nginx/sites-available/

sudo nginx -t && sudo systemctl reload nginx
```

`nginx -t` before any reload, without exception: it is what stops a broken
configuration from ever being loaded. A reload drops no in-flight connection,
unlike a restart, and it is what makes the two safe to run on a live server.

Wait a second before checking the result. A reload starts new worker processes
and lets the old ones finish what they are serving, so a request sent
immediately can be answered by the previous configuration and suggest a failure
that is not one.

**Checking that the server matches the repository**

```bash
cd /opt/taskflow
./scripts/check-nginx-sync.sh
```

Exit code `0` means the eight versioned files match what is deployed. The script
only reads, and reports both a divergent file and one missing from either side.

Three things are outside its reach and have to be checked by hand. The first is
`/etc/nginx/nginx.conf`, a dpkg conffile that is not versioned here: its
deliberate divergences are listed in
[`nginx/NGINX_CONF_CHANGES.md`](nginx/NGINX_CONF_CHANGES.md) and audited with
`sudo nginx -T | grep ssl_protocols`. The second is the absence of the
`sites-enabled/default` symlink, since an absence cannot be versioned. The third
is which vhosts are actually enabled: a file can match this check perfectly and
serve nothing at all, never having been symlinked.

---

## Backups

The production database is dumped every day at 03:00 UTC by
`scripts/backup-db.sh`, scheduled by a systemd timer. Dumps are written to
`/home/mehdi/backups`, kept for seven days, and a failure sends a push
notification to the maintainer.

**Install the timer** (once, after cloning):

```bash
sudo cp systemd/taskflow-backup.service /etc/systemd/system/
sudo cp systemd/taskflow-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now taskflow-backup.timer
```

**Check the schedule and the last run:**

```bash
systemctl list-timers taskflow-backup.timer
systemctl status taskflow-backup.service
journalctl -u taskflow-backup.service --since "7 days ago"
```

**Run one on demand:**

```bash
sudo systemctl start taskflow-backup.service
```

Backups live on the VPS disk, outside the Git working copy. They cover logical
damage — a bad migration, an accidental deletion — at table granularity. The
loss of the server itself is covered separately by Hetzner's daily snapshots,
which is why no off-site copy of these dumps is kept. See issue #17 and
[`SECURITY.md`](SECURITY.md).

Automated dumps are named `taskflow-auto_*.sql` and pruned after seven days.
Manual dumps named `taskflow_*.sql` are never pruned.

Restoring, and verifying that a backup is actually restorable, is documented in
[`docs/04-securite/DATABASE_RESTORE.md`](docs/04-securite/DATABASE_RESTORE.md).
A backup that has never been restored is not a backup.

---

## Environment Variables

Copy `.env.example` to `.env` and fill in real values.

| Variable | Description |
|----------|-------------|
| `MYSQL_ROOT_PASSWORD` | **Removed.** Since issue #20 the database receives its passwords through Docker Compose secrets, from files under `/home/mehdi/secrets/`, not from this file |
| `DB_HOST` | Database host — `taskflow-db` (Docker service name) |
| `DB_PORT` | Database port — `3306` |
| `DB_NAME` | Database name |
| `DB_USERNAME` | Application database user |
| `DB_PASSWORD`, `JWT_SECRET` | **Removed.** Since issue #38 both are Docker Compose secrets, files under `/home/mehdi/secrets/`, not variables of this file. `taskflow-api` reads them as `/run/secrets/db.password` and `/run/secrets/jwt.secret` |
| `JWT_EXPIRATION` | JWT expiry in milliseconds — default `900000` (15 min) |
| `COOKIE_SECURE` | Enable `Secure` flag on cookies — `true` in production |
| `REFRESH_TOKEN_EXPIRATION_DAYS` | Refresh token validity — default `7` days |
| `CORS_ALLOWED_ORIGINS` | Allowed CORS origins, comma-separated — `https://taskflow.mehdi-rochereau.dev,https://api.taskflow.mehdi-rochereau.dev` |
| `NTFY_TOPIC` | ntfy topic used by the backup script to report failures. Treat as a secret: anyone knowing the name can read and post to it |

The JWT secret is generated during step 5 and written straight to its file:

```bash
openssl rand -hex 64 | tr -d '\n' > /home/mehdi/secrets/jwt_secret
```

Database passwords are not generated this way. Use a password manager, 40
characters, alphanumeric, no special characters: `$`, quotes, backslash and
backtick all carry meaning in the shell, in `.env` and in SQL, and produce
failures that point nowhere near their cause.

---

## Security

- `.env` is excluded from version control via `.gitignore`
- `.env` permissions are restricted to `600` (owner read/write only), and it
  holds no password since issue #38
- No secret is passed as an environment variable to any container. Passwords and
  the JWT key are mounted as files under `/run/secrets/`, so `docker inspect`
  exposes a path rather than a value
- Docker images are private on GitHub Container Registry
- MySQL port is not exposed outside the Docker network
- All traffic is encrypted via HTTPS (Let's Encrypt)
- Nginx enforces HTTP → HTTPS redirection
- No credential is passed as a command-line argument, in the healthcheck or
  anywhere else. Process arguments are world-readable in `/proc`. The
  `taskflow-db` healthcheck authenticates as `healthcheck@'%'`, an account with
  no password and `USAGE` only, reaching no database, table or row
- Database credentials are rotated on exposure, on sharing, or on schedule:
  [`docs/04-securite/DATABASE_CREDENTIAL_ROTATION.md`](docs/04-securite/DATABASE_CREDENTIAL_ROTATION.md)

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