# Politique de Sécurité

> 🇬🇧 [English version](SECURITY.md)

## Présentation

Ce document décrit les mesures de sécurité infrastructure mises en place pour le
déploiement en production de TaskFlow sur VPS Hetzner.

TaskFlow est un projet portfolio démontrant des pratiques modernes de DevOps et de
sécurité avec Docker, Nginx, Let's Encrypt et Ubuntu 24.04.

---

## Versions supportées

| Version | Supportée |
|---------|-----------|
| 1.0.x   | ✅        |

---

## Mesures de sécurité

### Durcissement du serveur

- **Utilisateur non-root** — L'application tourne sous un utilisateur dédié `mehdi`
  avec privilèges sudo. La connexion directe en root est désactivée.
- **Authentification SSH par clé uniquement** — L'authentification par mot de passe
  est désactivée dans `/etc/ssh/sshd_config`. Seule l'authentification par clé
  publique Ed25519 est acceptée.
- **Pare-feu UFW** — Seuls les ports 22 (SSH), 80 (HTTP) et 443 (HTTPS) sont ouverts.
  Tout autre trafic entrant est bloqué par défaut.
- **Fail2ban** — Bannit automatiquement les IPs après 5 tentatives SSH échouées en
  10 minutes. Durée du bannissement : 1 heure.

### Sécurité Docker

- **Conteneurs non-root** — Le conteneur `taskflow-api` tourne sous un utilisateur
  `taskflow` dédié non-root. Le conteneur `taskflow-ui` tourne sous `nginx`.
- **Réseau interne** — Toute communication inter-conteneurs utilise un réseau bridge
  Docker privé (`taskflow-network`). MySQL n'est pas exposé au réseau hôte.
- **Publication des ports sur la boucle locale** — Les ports des conteneurs ne sont
  publiés que sur `127.0.0.1`. Nginx, qui tourne sur l'hôte, les atteint par la
  boucle locale ; ils ne sont pas joignables depuis l'extérieur du VPS.
- **Registry privé** — Les images Docker sont stockées de manière privée sur GitHub
  Container Registry (ghcr.io) et nécessitent une authentification pour être tirées.
- **Secrets en lecture restreinte** — Le fichier `.env` contenant les secrets de
  production possède les permissions `600` (lecture/écriture propriétaire uniquement).

### Sécurité du transport

- **HTTPS imposé** — Nginx redirige tout le trafic HTTP vers HTTPS via une redirection
  permanente `301`.
- **SSL Let's Encrypt** — Les certificats TLS sont émis par Let's Encrypt et renouvelés
  automatiquement via le timer systemd de Certbot.
- **HSTS** — `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  appliqué par l'API sur toutes les réponses.

### Sécurité Nginx

- **Reverse proxy** — Nginx est le seul point d'entrée. Les services backend ne sont
  pas directement accessibles depuis internet.
- **`server_tokens off`** — La version de Nginx est masquée des en-têtes de réponse.
- **robots.txt** — `taskflow.mehdi-rochereau.dev` et `api.taskflow.mehdi-rochereau.dev`
  retournent `Disallow: /` pour empêcher l'indexation par les moteurs de recherche.

### Gestion des secrets

- `.env` exclu du contrôle de version via `.gitignore`
- `.env` ne contient aucune valeur par défaut pour les secrets de production
- Le secret JWT est généré avec `openssl rand -hex 64` — 512 bits d'entropie
- Les mots de passe de base de données sont générés avec `openssl rand -hex 32` — 256 bits d'entropie
- Le token GitHub Container Registry a une portée minimale (`read:packages`, `write:packages`)

### Sécurité applicative

Toute la sécurité au niveau applicatif est documentée dans les dépôts respectifs :

- [taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
  — JWT, cookies HttpOnly, rate limiting, sanitisation des entrées, audit logging
- [taskflow-ui/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-ui/blob/main/SECURITY.md)
  — Prévention XSS, protection CSRF, guards de routes, silent refresh

---

## Principes de sécurité appliqués

| Principe | Implémentation |
|----------|----------------|
| **Défense en profondeur** | UFW + Fail2ban + clés SSH + isolation réseau Docker + reverse proxy Nginx |
| **Moindre privilège** | Utilisateur OS non-root, conteneurs non-root, token GitHub à portée minimale, MySQL interne |
| **Sécurité par défaut** | Login root désactivé, auth par mot de passe désactivée, tous les ports fermés par défaut |
| **Hygiène des secrets** | `.env` à `600`, exclu de git, aucune valeur par défaut pour les secrets de prod |
| **Chiffrement en transit** | HTTPS imposé, HSTS activé, renouvellement automatique Let's Encrypt |

---

## Limitations connues

### Architecture mono-serveur

Le déploiement actuel fait tourner tous les services sur un seul VPS. Cela implique :
- Pas de haute disponibilité — une panne serveur arrête tous les services
- Pas de mise à l'échelle horizontale — CPU et mémoire partagés entre API, UI et base de données
- Les sauvegardes reposent sur la fonctionnalité de snapshot automatique Hetzner (quotidien)

Un déploiement en conditions réelles utiliserait des serveurs de base de données séparés,
des load balancers et une plateforme d'orchestration de conteneurs telle que Kubernetes.

### Rate Limiting en mémoire

Le rate limiting est géré au niveau applicatif avec Bucket4j en stockage mémoire.
Un redémarrage du serveur remet tous les compteurs à zéro. Voir
[taskflow-api/SECURITY.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.md)
pour les détails.

---

## Améliorations prévues

- [ ] GitHub Actions CI/CD — pipeline automatisé de build, push et déploiement
- [ ] Watchtower — mise à jour automatique des images de conteneurs
- [ ] Gestion centralisée des logs
- [ ] Automatisation des sauvegardes de base de données

---

## Signaler une vulnérabilité

Si vous découvrez une vulnérabilité de sécurité dans ce projet, merci de la signaler
de manière responsable en contactant :

**Email :** mehdi.rochereau.dev@gmail.com

Merci d'inclure :
- Une description de la vulnérabilité
- Les étapes pour la reproduire
- L'impact potentiel

Ce projet est un portfolio et n'est pas destiné à un usage en production avec de
vraies données utilisateurs. Le délai de réponse peut varier.

---

## Liens associés

- [taskflow-api](https://github.com/mehdi-rochereau/taskflow-api) — API REST Spring Boot
- [taskflow-ui](https://github.com/mehdi-rochereau/taskflow-ui) — Frontend Angular
- [taskflow-api/SECURITY.fr.md](https://github.com/mehdi-rochereau/taskflow-api/blob/main/SECURITY.fr.md) — Politique de sécurité API
- [taskflow-ui/SECURITY.fr.md](https://github.com/mehdi-rochereau/taskflow-ui/blob/main/SECURITY.fr.md) — Politique de sécurité frontend