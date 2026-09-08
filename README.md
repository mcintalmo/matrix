# The Rumpus Room - Self-Hosted Matrix 2.0 Server

A production Matrix homeserver stack for [rumpusroom.xyz](https://element.rumpusroom.xyz), running on Oracle Cloud Infrastructure (OCI) Always Free ARM VPS (4 OCPU / 12GB RAM).

This repository utilizes declarative Infrastructure as Code (Terraform), Docker Compose, and automated configuration templating to deploy a modern Matrix 2.0 ecosystem optimized for privacy, performance, and low operational overhead.

---

## Architecture Overview

Matrix 2.0 decouples client sync traffic, user identity, and real-time WebRTC media from the core homeserver process.

```
Incoming Web & Client Traffic
  |
  v
Nginx (Reverse Proxy & TLS Termination)
  |
  +-- /_matrix/client/v3/sync       -> Synapse Generic Worker 1 (Port 8081)
  +-- /_matrix/client/v4/sync       -> Synapse Generic Worker 1 (Native Sliding Sync MSC4186)
  +-- /_matrix/federation/*         -> Synapse Federation Sender (Port 8083)
  +-- /_matrix/client/*/register    -> MAS (Matrix Authentication Service)
  +-- /_matrix/client/*/login       -> MAS (Matrix Authentication Service)
  +-- /_matrix/client/*/logout      -> MAS (Matrix Authentication Service)
  +-- /_matrix/client/*/refresh     -> MAS (Matrix Authentication Service)
  +-- /_matrix/client/versions      -> Synapse Main (Port 8008)
  +-- /.well-known/matrix/*         -> Static Client & Server Delegation
  +-- /rageshake                    -> FastAPI Rageshake Webhook (Bug reporting with Gmail SMTP)
  +-- /_grafana/                    -> Grafana Observability Dashboard (Basic Auth Protected)
  +-- element.rumpusroom.xyz        -> Element Web Client (Port 80)
  +-- call.rumpusroom.xyz           -> Element Call MatrixRTC Client (Port 80)
  +-- livekit.rumpusroom.xyz        -> LiveKit SFU WebRTC Signaling (Port 7880)
```

### Core Components
- **Synapse (Matrix 2.0)**: Homeserver with native Sliding Sync (MSC4186) enabled, Redis-backed event bus, and dedicated sync workers.
- **MAS (Matrix Authentication Service)**: MSC3861 auth provider delegating logins to Discord SSO, Google SSO, and local argon2id accounts. Upstream email claims are imported and auto-verified.
- **LiveKit SFU & Coturn**: High-performance multi-party WebRTC audio/video SFU with adaptive streaming and dynacast, paired with Coturn for STUN/TURN fallback.
- **Element Web & Element Call**: Modern web clients configured for MatrixRTC and Sliding Sync.
- **Rageshake Webhook**: Python FastAPI microservice handling Element bug reports, log forwarding, and Gmail SMTP alerts.
- **Telemetry**: Prometheus, Alertmanager, and Grafana for monitoring resource budgets, query latencies, and sync performance.

---

## Installation & Deployment

### 1. Prerequisites
- [Terraform](https://www.terraform.io/) >= 1.5
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with your Oracle Cloud credentials
- Public DNS A-records configured for all 8 domains pointing to your server IP (`147.224.210.130`):
  - `rumpusroom.xyz`
  - `matrix.rumpusroom.xyz`
  - `element.rumpusroom.xyz`
  - `chat.rumpusroom.xyz`
  - `call.rumpusroom.xyz`
  - `livekit.rumpusroom.xyz`
  - `turn.rumpusroom.xyz`
  - `auth.rumpusroom.xyz`

### 2. Provision Cloud Infrastructure
Deploy network security lists, compute instance, and storage via Terraform:
```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Fill in your OCI tenancy and compartment OCIDs
make tf-init
make tf-plan
make tf-apply
```

### 3. Initialize Environment & Secrets
Generate cryptographically random credentials, MAS RSA signing keys, and Docker secrets:
```bash
# Generate .env with secure random secrets
make init-env

# Pre-flight validation of environment variables and template schemas
make check
```

### 4. Deploy Application Stack
Deploy code, render configuration templates, and start the Docker containers:
```bash
# Deploys code to server via rsync and automatically compiles configuration templates
make deploy

# Or deploy the .env file if updated
make deploy-env
```

### 5. First-Time Server Bootstrapping
On the server (or via SSH targets in the Makefile):
```bash
# Setup Synapse data directory and permissions
make setup-synapse

# Obtain Let's Encrypt certificates for all 8 domains
make setup-ssl

# Start all containers
make docker-up
```

---

## Operational CLI: `scripts/matrix-ctl`

The repository includes a non-interactive CLI for automated operations and CI/CD:

```bash
# Pre-flight verification
./scripts/matrix-ctl check

# Compile configuration templates (.template -> config)
./scripts/matrix-ctl render

# Human-readable status report
./scripts/matrix-ctl status

# Machine-readable JSON status report (for automation and monitoring)
./scripts/matrix-ctl status --json

# Issue an account registration token (valid for 365 days)
./scripts/matrix-ctl token --days 365

# Create an administrator account non-interactively
./scripts/matrix-ctl create-admin --username admin --password <SECURE_PASSWORD> --email admin@rumpusroom.xyz
```

---

## Making Configuration Changes

This repository enforces declarative Infrastructure as Code. **Never modify rendered configuration files directly on the server.**

1. Edit the appropriate template locally:
   - `synapse/homeserver.yaml.template`
   - `mas/config.yaml.template`
   - `nginx/nginx.conf.template`
   - `livekit/config.yaml.template`
   - `element-web/config.json.template`
   - `element-call/config.json.template`
2. Test the rendering locally:
   ```bash
   make render
   ```
3. Deploy to the server:
   ```bash
   make deploy
   ```
4. Restart the affected container:
   ```bash
   make docker-restart SERVICE=synapse
   ```

---

## Backups & Disaster Recovery

Backups are executed via `scripts/backup.sh` and stream compressed Postgres dumps, media archives, and configuration snapshots into OCI Object Storage using Instance Principal authentication.

```bash
# Trigger an immediate backup
make backup

# List available backups in OCI Object Storage
make list-backups

# Restore from the latest available backup
make restore

# Restore from a specific timestamp (e.g., March 1, 2026)
make restore TIME=20260301
```

---

## Developer Quality Standards

Python components (including `rageshake-webhook/`) adhere to modern testing and typing standards:

```bash
# Run unit test suite
make test

# Run code linter and formatter
make lint
```
