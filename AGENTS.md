# AGENTS.md - Agentic AI Development Guidelines

This document establishes operational conventions, architectural rules, and development standards for AI agents working in this repository.

---

## 1. Core Architecture & Mental Model

This repository hosts a production Matrix 2.0 communication stack deployed on an Oracle Cloud Infrastructure (OCI) ARM64 Ubuntu instance (`147.224.210.130`).

### Services Overview
- **Matrix Homeserver**: Synapse (`matrixdotorg/synapse:latest`) running Matrix 2.0 with native Sliding Sync (MSC4186) and generic worker delegation for `/sync`, `/events`, and `/initialSync`.
- **Authentication**: Matrix Authentication Service (`matrix-authentication-service:latest`), delegated via MSC3861 as the single authority for user accounts, passwords, Discord SSO, Google SSO, and registration tokens.
- **WebRTC / MatrixRTC**: LiveKit SFU (`livekit/livekit-server:latest`) for scalable multi-party voice/video conferencing, backed by Coturn (`coturn/coturn:latest`) for NAT traversal / STUN / TURN fallback.
- **Web Clients**: Element Web (`vectorim/element-web:latest`) and Element Call (`vectorim/element-call:latest`).
- **Telemetry & Error Reporting**: Prometheus, Grafana, Alertmanager, and a dedicated FastAPI Rageshake Webhook (`rageshake-webhook/`) for handling client bug reports with email escalation.
- **Reverse Proxy**: Nginx orchestrating routing, WebSockets, rate limiting, and Let's Encrypt SSL across 8 FQDNs.

---

## 2. Declarative Infrastructure as Code (IaC) Rules

### Never Modify Compiled Configuration Files Directly
All primary service configuration files are dynamically compiled from templates:
- Edit `synapse/homeserver.yaml.template` -> Compiles to `synapse/homeserver.yaml`
- Edit `mas/config.yaml.template` -> Compiles to `mas/config.yaml`
- Edit `nginx/nginx.conf.template` -> Compiles to `nginx/nginx.conf`
- Edit `livekit/config.yaml.template` -> Compiles to `livekit/config.yaml`
- Edit `element-web/config.json.template` -> Compiles to `element-web/config.json`
- Edit `element-call/config.json.template` -> Compiles to `element-call/config.json`
- Edit `telemetry/alertmanager.yml.template` -> Compiles to `telemetry/alertmanager.yml`

To recompile configurations:
```bash
make render
# OR
./scripts/matrix-ctl render
```

### Scoped Environment Substitution
When modifying `nginx/nginx.conf.template`, be aware that Nginx internal variables (such as `$host`, `$remote_addr`, `$http_upgrade`) will be erased if run through a bare `envsubst`. The compilation command in `scripts/matrix-ctl render` explicitly scopes variables:
```bash
envsubst '${DOMAIN} ${MATRIX_FQDN} ${ELEMENT_WEB_FQDN} ${ELEMENT_CALL_FQDN} ${LIVEKIT_FQDN} ${CHAT_FQDN} ${CALL_FQDN}' < nginx/nginx.conf.template > nginx/nginx.conf
```

---

## 3. Tooling & Language Standards

### Style & Output Constraints
- Strictly avoid emojis in all code, comments, scripts, command output, commit messages, and documentation.
- Use explicit bracketed status tags: `[OK]`, `[INFO]`, `[WARN]`, `[ERROR]`, `[PASS]`, `[FAIL]`.

### Python Guidelines
- Package and virtual environment management: `uv`.
- Testing framework: `pytest`. Unit tests reside in `rageshake-webhook/test_main.py`.
- Linter and formatter: `ruff check .`
- Type safety: Static typing annotations required on all function definitions.
- Commands:
  ```bash
  make test    # Runs uv run pytest rageshake-webhook
  make lint    # Runs uv run ruff check .
  ```

### JavaScript / JSON Guidelines
- Use Biome to lint and format any JavaScript or JSON files.

---

## 4. Operational CLI: `matrix-ctl`

All automation, maintenance, and diagnostics should go through `scripts/matrix-ctl` or corresponding `Makefile` targets. Never rely on deprecated procedural scripts in `.archive/scripts/`.

### Commands
- Pre-flight Validation:
  ```bash
  ./scripts/matrix-ctl check
  # Exit code 0 if all required env vars, templates, and compose syntax pass.
  ```
- Compile Configuration:
  ```bash
  ./scripts/matrix-ctl render
  ```
- Machine-Readable System Status:
  ```bash
  ./scripts/matrix-ctl status --json
  # Returns structured JSON with service health, system memory, disk, and container list.
  ```
- Issue Registration Tokens:
  ```bash
  ./scripts/matrix-ctl token --days 365
  # Issues a registration token and automatically updates postgres DB expiry to 365 days.
  ```
- Non-Interactive Admin User Creation:
  ```bash
  ./scripts/matrix-ctl create-admin --username admin --password <SECURE_PASS> --email admin@rumpusroom.xyz
  ```

---

## 5. Network Architecture & Egress Trap

Docker containers default to the `internal` network, which specifies `internal: true`.
- An `internal: true` Docker network completely blocks external internet access (egress).
- Containers that require outbound connectivity (Synapse for federation and SMTP, Alertmanager for notifications, and Rageshake Webhook for Gmail SMTP forwarding) MUST have both `backend` and `egress` networks attached in `docker-compose.yml`.

---

## 6. Resource Budgets on OCI ARM VPS

The target server has 12GB RAM and 4 ARM OCPUs.
- Synapse cache limit: 2048M.
- Postgres shared buffers: 1024M, work_mem: 64M.
- Jaeger tracing: Retained under Docker Compose profile `profiles: ["debug"]` so it does not consume 512MB RAM during normal production runs. Do not remove this profile constraint unless explicitly debugging distributed traces.
