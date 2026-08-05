# TaskFlow Deploy

> 🇬🇧 [English version](README.md)

Configuration de déploiement en production pour l'application TaskFlow — stack Docker Compose, reverse proxy Nginx, certificats SSL et scripts de déploiement.

[![Docker](https://img.shields.io/badge/Docker-26-2496ED?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Nginx](https://img.shields.io/badge/Nginx-1.24-009639?style=flat&logo=nginx&logoColor=white)](https://nginx.org/)
[![Let's Encrypt](https://img.shields.io/badge/SSL-Let's%20Encrypt-003A70?style=flat&logo=letsencrypt&logoColor=white)](https://letsencrypt.org/)
[![Hetzner](https://img.shields.io/badge/VPS-Hetzner-D50C2D?style=flat&logo=hetzner&logoColor=white)](https://www.hetzner.com/)

---

## Présentation

Ce dépôt contient la configuration d'infrastructure en production pour TaskFlow.
Il orchestre trois conteneurs Docker — MySQL, l'API Spring Boot et l'interface Angular —
derrière un reverse proxy Nginx avec certificats SSL Let's Encrypt sur un VPS Hetzner.

🌐 **En ligne :** [taskflow.mehdi-rochereau.dev](https://taskflow.mehdi-rochereau.dev)
📖 **Documentation API :** [api.taskflow.mehdi-rochereau.dev/swagger-ui/index.html](https://api.taskflow.mehdi-rochereau.dev/swagger-ui/index.html)

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
    ├── Nginx (reverse proxy — terminaison SSL, routage)
    │       ├── → taskflow-ui  (port 4000)
    │       └── → taskflow-api (port 8082)
    │
    └── Docker Compose
            ├── taskflow-api  (Spring Boot 3.5 / Java 21)
            ├── taskflow-ui   (Angular 21 + Nginx)
            └── taskflow-db   (MySQL 8.0)
```

---

## Structure du dépôt

```
taskflow-deploy/
├── docker-compose.yml     # Définition de la stack Docker Compose
├── .env.example           # Modèle de variables d'environnement
├── .gitignore             # Exclut .env et les secrets
├── scripts/
│   ├── deploy.sh          # Script de déploiement en production
│   └── .gitattributes     # Configuration des fins de ligne
└── README.md
```

---

## Infrastructure

| Composant | Détails |
|-----------|---------|
| VPS | Hetzner CPX22 — 2 vCPU, 4 Go RAM, 80 Go SSD |
| OS | Ubuntu 24.04 LTS |
| Reverse Proxy | Nginx 1.24 |
| SSL | Let's Encrypt — renouvellement automatique via Certbot |
| Runtime | Docker 26 + Docker Compose v2 |
| Registry | GitHub Container Registry (ghcr.io) |

---

## Services

| Service | Image | Port | Description |
|---------|-------|------|-------------|
| `taskflow-db` | `mysql:8.0` | — | Base de données MySQL (réseau interne uniquement) |
| `taskflow-api` | `ghcr.io/mehdi-rochereau/taskflow-api:latest` | `8082` | API REST Spring Boot |
| `taskflow-ui` | `ghcr.io/mehdi-rochereau/taskflow-ui:latest` | `4000` | Frontend Angular |

---

## Prérequis

- VPS sous Ubuntu 24.04
- Docker et Docker Compose installés
- Nginx et Certbot installés
- Enregistrements DNS pointant vers l'IP du VPS
- Accès GitHub Container Registry configuré

---

## Installation initiale du serveur

**1. Installer Docker**

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

**2. Installer Nginx et Certbot**

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

**3. Cloner ce dépôt**

```bash
sudo mkdir -p /opt/taskflow
sudo chown $USER:$USER /opt/taskflow
cd /opt/taskflow
git clone https://github.com/mehdi-rochereau/taskflow-deploy.git .
```

**4. Configurer les variables d'environnement**

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

**5. S'authentifier sur GitHub Container Registry**

```bash
echo "VOTRE_TOKEN_GITHUB" | docker login ghcr.io -u VOTRE_NOM_UTILISATEUR --password-stdin
```

**6. Configurer Nginx**

```bash
sudo nano /etc/nginx/sites-available/taskflow
sudo nano /etc/nginx/sites-available/api-taskflow
sudo ln -s /etc/nginx/sites-available/taskflow /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/api-taskflow /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

**7. Générer les certificats SSL**

```bash
sudo certbot --nginx -d taskflow.mehdi-rochereau.dev -d api.taskflow.mehdi-rochereau.dev
```

---

## Déploiement

**Tirer les images et démarrer la stack**

```bash
docker compose pull
docker compose up -d
```

**Via le script de déploiement**

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Le script tire automatiquement les dernières images, redémarre la stack et vérifie le healthcheck de l'API.

**Vérifier l'état des services**

```bash
docker compose ps
docker compose logs taskflow-api --tail=50
```

---

## Variables d'environnement

Copier `.env.example` vers `.env` et renseigner les vraies valeurs.

| Variable | Description |
|----------|-------------|
| `MYSQL_ROOT_PASSWORD` | Mot de passe root MySQL — usage interne uniquement |
| `DB_HOST` | Hôte de la base — `taskflow-db` (nom du service Docker) |
| `DB_PORT` | Port de la base — `3306` |
| `DB_NAME` | Nom de la base de données |
| `DB_USERNAME` | Utilisateur applicatif de la base |
| `DB_PASSWORD` | Mot de passe de l'utilisateur applicatif |
| `JWT_SECRET` | Clé de signature HMAC-SHA512 — minimum 32 caractères |
| `JWT_EXPIRATION` | Durée de validité du JWT en millisecondes — défaut `900000` (15 min) |
| `COOKIE_SECURE` | Active le flag `Secure` sur les cookies — `true` en production |
| `REFRESH_TOKEN_EXPIRATION_DAYS` | Validité du refresh token — défaut `7` jours |
| `CORS_ALLOWED_ORIGINS` | Origine CORS autorisée — `https://taskflow.mehdi-rochereau.dev` |

Générer un secret JWT sécurisé :

```bash
openssl rand -hex 64
```

---

## Sécurité

- `.env` exclu du contrôle de version via `.gitignore`
- Permissions du `.env` restreintes à `600` (lecture/écriture propriétaire uniquement)
- Images Docker privées sur GitHub Container Registry
- Port MySQL non exposé en dehors du réseau Docker interne
- Tout le trafic chiffré via HTTPS (Let's Encrypt)
- Nginx applique la redirection HTTP → HTTPS

Pour les détails de sécurité au niveau applicatif, voir :
- [taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
- [taskflow-ui/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-ui/blob/main/SECURITY.md)

---

## Améliorations prévues

- [ ] GitHub Actions CI/CD — build, push et déploiement automatiques sur push `main`
- [ ] Watchtower — mise à jour automatique des conteneurs
- [ ] Rotation des logs et centralisation

---
 
## Gestion de projet & Documentation
 
Les trois dépôts TaskFlow sont pilotés depuis un
[GitHub Project](https://github.com/users/mehdi-rochereau/projects/4) unique :
issue d'abord, branche créée depuis l'issue, pull request, squash merge, avec un
flux à cinq statuts (Backlog → In Progress → In Review → Verifying → Done).
 
La documentation transverse vit dans [`docs/`](docs/), dont le manuel complet de
gestion de projet :
[`docs/02-gestion-de-projet/PROJECT_MANAGEMENT.md`](docs/02-gestion-de-projet/PROJECT_MANAGEMENT.md).

---

## Écosystème

| Dépôt | Description |
|-------|-------------|
| [taskflow-deploy](https://github.com/mehdi-rochereau/taskflow-deploy) | Configuration de déploiement (ce dépôt) |
| [taskflow-api](https://github.com/mehdi-rochereau/taskflow-api) | API REST Spring Boot |
| [taskflow-ui](https://github.com/mehdi-rochereau/taskflow-ui) | Frontend Angular |