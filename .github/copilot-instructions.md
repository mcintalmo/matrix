# Project Context: The Rumpus Room (Matrix/Synapse Stack)

## 1. High-Level Goal
We are building a private, self-hosted Matrix chat server for a group of friends. The priority is a "Discord-like" experience but with modern Matrix architecture (OIDC Authentication).
- **Domain:** `rumpusroom.xyz`
- **Infrastructure:** Oracle Cloud Free Tier (ARM64 / Ampere A1 Compute).
- **Deployment Method:** Docker Compose (Single Host).

## 2. The Stack (Architecture)
We are using the "Modern" Matrix stack, not the legacy one.
- **Homeserver:** Synapse (latest Docker image).
- **Database:** PostgreSQL (handling databases for both Synapse and MAS).
- **Authentication:** Matrix Authentication Service (MAS) handling OIDC/OAuth2.
  - *Note:* Synapse must be configured for delegated auth (MSC3861).
  - *Note:* We are NOT using the built-in Synapse password provider.
- **Reverse Proxy:** Nginx (handling SSL termination and routing).
  - Routes `/_matrix` -> Synapse
  - Routes `/_synapse/client` -> Synapse
  - Routes `/_auth`, `/oauth2`, `/.well-known/openid-configuration` -> MAS
- **Frontend (Web):** Element Web (hosted at `element.rumpusroom.xyz`).
- **Frontend (Mobile):** Users must use **Element X** (since the legacy Element app does not fully support OIDC/MAS).

## 3. Configuration Goals
- Domain: `rumpusroom.xyz`
- Subdomain for Matrix: `matrix.rumpusroom.xyz`
- Subdomain for Element: `element.rumpusroom.xyz`
- The setup must run locally via `docker compose up`.
- Nginx should proxy traffic to Synapse on port 8008.
- Postgres must be configured with a user and database for Synapse.

## 4. Constraints

- **Security:** Do not output real passwords for production credentials; use placeholders like `POSTGRES_PASSWORD_HERE`.
- **Persistence:** All data (Synapse media, Postgres data, Nginx configs) must be persisted using Docker volumes or bind mounts.
- **Local Dev:** The configuration should be runnable locally for testing, but structured for easy deployment to the VPS.

## 5. Key Configuration Decisions

- **Secure Backups:** We are enforcing "Tough Love." The server must require users to set up Secure Backup (Recovery Key) immediately upon registration to prevent "Verified Session" confusion later.
- **Registration:** Open registration is disabled. We will use **Registration Tokens** (managed via MAS) to invite friends.
- **Encryption:** End-to-End Encryption (E2EE) is ENABLED by default.

## 6. Domain & DNS Map
- `matrix.rumpusroom.xyz` (A Record) -> Oracle IP (Synapse Backend)
- `element.rumpusroom.xyz` (A Record) -> Oracle IP (Element Web)

## 7. Documentation & References (Source of Truth)
- **MAS (Matrix Authentication Service) Docs:** https://element-hq.github.io/matrix-authentication-service/
- **Synapse MSC3861 Config:** https://element-hq.github.io/matrix-authentication-service/setup/synapse.html
- **Element Web Config:** https://github.com/element-hq/element-web/blob/develop/docs/config.md
- [Installation](https://element-hq.github.io/synapse/latest/setup/installation.html)
- [Security](https://element-hq.github.io/synapse/latest/setup/security.html)
- [Docker Image](https://hub.docker.com/r/matrixdotorg/synapse)
- [Ansible Quickstart](https://github.com/spantaleev/matrix-docker-ansible-deploy/blob/master/docs/quick-start.md)
- [PostGres](https://element-hq.github.io/synapse/latest/setup/installation.html#using-postgresql)
- [Reverse Proxy (Nginx)](https://element-hq.github.io/synapse/latest/reverse_proxy.html#nginx)
- [Matrix Authentication Service (MAS)](https://element-hq.github.io/matrix-authentication-service/setup/installation.html#using-the-docker-image)
- [UV for Python](https://docs.astral.sh/uv/)