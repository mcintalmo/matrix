# The Rumpus Room — Self-Hosted Matrix Server

A production-ready Matrix homeserver stack for [rumpusroom.xyz](https://element.rumpusroom.xyz), running on Oracle Cloud Infrastructure.

## Architecture

```
Browser → Nginx (HTTPS) ─┬─ /_matrix/*   → Synapse (homeserver)
                          ├─ /_synapse/*  → Synapse (admin)
                          ├─ /*           → MAS (auth service)
                          └─ element.*       → Element (web client)

Synapse → PostgreSQL (database)
MAS     → PostgreSQL (database)
MAS     ← Discord / Google (OIDC providers)
MAS     ← Gmail SMTP (email registration & recovery)
```

**Services:**

| Container | Role |
|---|---|
| `nginx` | Reverse proxy, TLS termination, HTTP→HTTPS redirect |
| `synapse` | Matrix homeserver (Element/Synapse) |
| `mas` | Matrix Authentication Service — OIDC + email auth |
| `element` | Element Web client |
| `postgres` | PostgreSQL 15 — shared by Synapse and MAS |

**Infrastructure:** Oracle Cloud ARM64 A1.Flex (4 OCPUs, 24 GB RAM) — Always Free tier.

---

## Prerequisites

- [Terraform](https://www.terraform.io/) ≥ 1.5
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with your Oracle Cloud account
- An SSH keypair at `~/.ssh/id_ed25519`
- DNS for `matrix.rumpusroom.xyz` and `element.rumpusroom.xyz` pointing at the server IP

---

## Quick Start — Fresh Server Rebuild


```bash
# 1. Provision infrastructure
make update-ip          # Whitelist your current IP for SSH
make tf-apply           # Create VPS, VCN, backup bucket, IAM policies

# 2. Deploy app files (after adding GitHub Secrets — see below)
make deploy

# 3. SSH in and run first-time server setup
make ssh
cd /opt/matrix/app && ./scripts/server-setup.sh

# 4. Issue SSL certificates (first time only)
sudo certbot certonly --webroot -w /var/www/certbot \
  -d matrix.rumpusroom.xyz -d element.rumpusroom.xyz

# 5. Start the stack
docker compose up -d
```

---

## Day-to-Day Operations

```bash
make deploy             # Push local changes to server
make status             # Check all container health
make ssh                # Open SSH session
make docker-logs SERVICE=synapse  # Tail a service's logs
make backup             # Trigger a manual backup now
make update-ip          # Update your IP in the firewall (if it changed)
```

> **Full command reference:** run `make help`

---

## Secrets & Configuration

### How secrets work

This project does **not** commit secrets. They are stored in **GitHub Actions Secrets** and injected at deploy time by the CI/CD workflow.

| Secret Name | Description |
|---|---|
| `SSH_PRIVATE_KEY` | Private key for server access (`cat ~/.ssh/id_ed25519`) |
| `SERVER_IP` | Oracle VPS public IP |
| `POSTGRES_PASSWORD` | Shared Postgres superuser password |
| `MAS_SYNAPSE_SHARED_SECRET` | Shared secret between MAS and Synapse |
| `MAS_ADMIN_TOKEN` | MAS admin API token |
| `MAS_ENCRYPTION_SECRET` | MAS encryption key |
| `DISCORD_CLIENT_ID` | Discord OAuth2 client ID |
| `DISCORD_CLIENT_SECRET` | Discord OAuth2 client secret |
| `GOOGLE_CLIENT_ID` | Google OAuth2 client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth2 client secret |
| `GMAIL_APP_PASSWORD` | Gmail App Password for SMTP |
| `SYNAPSE_SIGNING_KEY` | Synapse server signing key — **never rotate this** |

Add secrets at: `GitHub → Settings → Secrets and variables → Actions`

### Local development

```bash
cp .env.example .env
# Fill in your values
```

The `.env` file is gitignored. The deployed `.env` on the server is written by the GitHub Actions workflow.

---

## CI/CD

Pushing to `main` triggers `.github/workflows/deploy.yml`, which:
1. Writes `.env` from GitHub Secrets
2. Writes the Synapse signing key from `SYNAPSE_SIGNING_KEY` secret
3. rsyncs all files to the server
4. Runs `docker compose up -d --remove-orphans`
5. Prints container status

---

## Infrastructure (Terraform)

Terraform manages all Oracle Cloud resources in `infra/`:

| Resource | Description |
|---|---|
| VCN + Subnet + Security List | Network with ports 22, 80, 443, 8448, 3478 open |
| `VM.Standard.A1.Flex` | ARM64 compute instance (Always Free) |
| Internet Gateway + Route Table | Public internet access |
| `matrix-backups` OCI bucket | Object Storage for daily backups |
| Dynamic Group + IAM Policy | Instance Principal auth for backup script |
| Budget Alert | Alerts if spending exceeds $1/month |

```bash
make tf-plan     # Preview changes
make tf-apply    # Apply changes
make tf-output   # Show outputs (IP, bucket URL, etc.)
```

> **Note:** `terraform.tfvars` contains your OCI credentials and is gitignored. See `infra/terraform.tfvars.example`.

---

## Backups

Daily backups run at **10:00 UTC** via cron and ship to Oracle Object Storage (`matrix-backups` bucket). Backups older than 30 days are automatically pruned.

**What's backed up:**
- PostgreSQL full dump (all databases)
- Synapse media store
- Config file snapshot

```bash
make backup                      # Trigger a manual backup now
make restore                     # Restore from most recent backup
make restore TIME=20260301       # Restore from nearest backup before Mar 1
make list-backups                # Show all available backups in OCI
```

---