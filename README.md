# The Rumpus Room — Self-Hosted Matrix Server

A Matrix homeserver stack for [rumpusroom.xyz](https://element.rumpusroom.xyz), running securely on Oracle Cloud Infrastructure free-tier.

This repository uses Infrastructure as Code (Terraform), Docker Compose, and automated configuration templating to deploy a modular Matrix ecosystem optimized for resource efficiency.

## Architecture

Our stack scales Matrix out across multiple dedicated workers while fitting entirely within an Oracle Free Tier 2-OCPU / 12GB RAM limit.

```
Browser / App
  │
  ▼
Nginx (Reverse Proxy & TLS Termination)
  │
  ├─ /_matrix/*         → Synapse Generic Worker (Sync & Client Traffic)
  ├─ /_matrix/federation→ Synapse Federation Sender (Server-to-Server Traffic)
  ├─ /_synapse/admin/*  → Synapse Main (Admin API)
  ├─ /.well-known/*     → Nginx Static Routing
  ├─ /*                 → Matrix Authentication Service (OIDC & Email Auth)
  ├─ /grafana           → Grafana Telemetry Dashboard (Protected via Basic Auth)
  └─ element.*          → Element Web (React Client)
```

### Core Services:
*   **Synapse (Main + Workers):** The Matrix backend. We use a Redis-backed distributed worker topology to separate heavy sync/federation traffic from the main process.
*   **PostgreSQL 15:** The central database serving both Synapse and MAS on separate schemas.
*   **MAS (Matrix Authentication Service):** Next-generation MSC3861 authentication delegating login to Discord, Google, and local secure passwords.
*   **Element Web & Call:** The beautifully customized web client and voice/video conferencing drop UI.
*   **LiveKit & Coturn:** Next-generation WebRTC SFU engine for seamless multi-user screen sharing and video calls.
*   **OpenTelemetry & Prometheus:** Comprehensive system instrumentation and metric scraping.

---

## Installation & Deployment

This repository is designed so that NO secrets are committed. All secrets are managed dynamically.

### 1. Prerequisites
- [Terraform](https://www.terraform.io/) ≥ 1.5
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with your Oracle Cloud account
- Required DNS records pointing to your server (`matrix.rumpusroom.xyz`, `element.rumpusroom.xyz`, `livekit.rumpusroom.xyz`, `turn.rumpusroom.xyz`)

### 2. Provision Infrastructure
We use Terraform to physically provision the Oracle Cloud VM instances and networking routes.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Fill out your Oracle Cloud compartment and tenancy OCIDs
terraform init
terraform apply
```

### 3. Local Configuration
Before deploying the Docker stack, configure your local environment and secrets. 

```bash
cp .env.example .env
# Fill in your OIDC Client IDs, Domains, and Passwords in .env

# Generate unique cryptographic secrets (LiveKit keys, Postgres passwords, etc)
./scripts/init.sh
```

### 4. Deploy to Server
We utilize an automated shell script to aggressively compile structural templates via `envsubst`, inject your local `.env` values, and sequentially `rsync` the production configuration to the Oracle VPS over SSH.

```bash
./scripts/deploy.sh
# Follow the interactive prompt, select option 1 (rsync)
```

### 5. Start the Stack & Initialize DB
```bash
# SSH into the server once deployment finishes
ssh ubuntu@<YOUR_SERVER_IP>
# or use the alias
# make ssh

# Spin up the infrastructure
cd /opt/matrix/app
docker compose up -d

# Initialize the MAS / Synapse databases (Only required on first boot)
make mas-init
```

---

## Making Changes

Because this project relies on rendered configuration templates, **never edit the configuration on the remote server!**

Instead, to modify the architecture or change configurations:
1. Edit the respective `*.template` file locally (e.g. `mas/config.yaml.template`).
2. Run `./scripts/deploy.sh` to compile your templates and push them to the server.
3. SSH into the server and restart the affected container:
```bash
ssh ubuntu@SERVER
cd /opt/matrix/app
docker compose restart <container_name>
```

---

## Telemetry & Observability

This stack features a built-in OpenTelemetry collector, Prometheus time-series database, and Grafana UI to monitor CPU utilization, request latency, and active Matrix users.

**Accessing Telemetry:**
*   Navigate to: `https://matrix.rumpusroom.xyz/grafana`
*   The dashboard is safely locked behind Nginx Basic Authentication.
*   **Username:** `admin`
*   **Password:** Located in `/secrets/grafana_password` (auto-generated during `./scripts/init.sh`)

**What's monitored:**
*   **Prometheus:** Scrapes Synapse metrics (sync time, cache evictions), MAS active logins, and Docker container CPU/Memory overhead.
*   **Alertmanager:** Listens for critical infrastructure failures (e.g. `InstanceDown`) and fires notification events.

---

## Features & Operations

### Registration Tokens
Account registration is highly restricted. To generate a single-use sign up token for a friend:
```bash
make registration-token
# Output: Registration Token: xYzAbC123
```

### Automated Backups
Daily backups run via cron on the server and stream directly into Oracle Object Storage.
```bash
make backup                      # Trigger a manual backup now
make restore                     # Restore from most recent backup
make restore TIME=20260301       # Restore from nearest backup before Mar 1
make list-backups                # Show all available backups in OCI
```

### Upgrading Services
To update Synapse or MAS to the latest container releases seamlessly:
```bash
# On the remote server
docker compose pull
docker compose up -d
docker system prune -f
```
