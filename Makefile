.PHONY: help check render update-ip deploy init-env setup-synapse setup-ssl tf-init tf-validate tf-fmt tf-plan tf-apply tf-destroy ssh logs status clean test lint harden-host audit vpn-user vpn-key vpn-nodes

# Variables
TERRAFORM_DIR := infra
SERVER_IP := $(shell cd $(TERRAFORM_DIR) && terraform output -raw server_public_ip 2>/dev/null || echo "not-deployed")

# Detect whether we are running on the server or locally.
# IS_SERVER=true when the server's app directory exists (i.e. we are already SSH'd in).
IS_SERVER := $(shell [ -f /opt/matrix/app/docker-compose.yml ] && echo true || echo false)

# SSH helper
SSH_RUN  = ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP)
SSH_RUN_T = ssh -i ~/.ssh/id_ed25519 -t ubuntu@$(SERVER_IP)
APP_DIR  = /opt/matrix/app

help: ## Show this help message
	@echo "=========================================================="
	@echo "  Matrix Synapse / MAS / LiveKit Stack Management"
	@echo "=========================================================="
	@echo ""
	@echo "Quick Start Commands:"
	@echo "  make check              - Validate configurations, templates, and environment"
	@echo "  make render             - Compile all .template files to configs"
	@echo "  make update-ip          - Update your IP and apply to firewall"
	@echo "  make deploy             - Deploy files to server (auto-renders templates)"
	@echo "  make status             - Report server and container status"
	@echo "  make token              - Generate a 365-day MAS registration token"
	@echo ""
	@echo "All Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ============================================================================
# Core Automation & Pre-Flight
# ============================================================================

check: ## Pre-flight validation of configuration, templates, and environment
	@./scripts/matrix-ctl check

render: ## Compile all configuration templates (.template -> config)
	@./scripts/matrix-ctl render

# ============================================================================
# Local Development & Deployment
# ============================================================================

update-ip: ## Detect current IP and update terraform config
	@./scripts/update-ip.sh

deploy: ## Deploy files from local to server (rsync + auto-render)
	@./scripts/deploy.sh

init-env: ## Generate .env file with secure secrets
	@./scripts/init-env.sh

deploy-env: ## Deploy local .env file to server
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "[ERROR] Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@if [ ! -f .env ]; then \
		echo "[ERROR] No .env file found locally. Run 'make init-env' first"; \
		exit 1; \
	fi
	@echo "Deploying .env file to server..."
	@rsync -avz -e "ssh -i ~/.ssh/id_ed25519" .env ubuntu@$(SERVER_IP):/opt/matrix/app/.env
	@echo "[OK] .env file deployed"
	@echo "[INFO] Restart services to apply: make docker-up"

# ============================================================================
# Server-Side Setup & Certificates
# ============================================================================

setup-synapse: ## Setup Synapse data directory with correct permissions
	@./scripts/setup-synapse.sh

setup-ssl: ## Setup SSL certificates for all 8 domains (on server)
	@./scripts/setup-ssl.sh

# ============================================================================
# DNS & Architecture
# ============================================================================

check-dns: ## Verify DNS configuration for matrix and element domains
	@echo "Checking DNS configuration..."
	@echo ""
	@echo "Matrix Backend (matrix.rumpusroom.xyz):"
	@dig +short matrix.rumpusroom.xyz || echo "[ERROR] Not configured"
	@echo ""
	@echo "Element Frontend (element.rumpusroom.xyz):"
	@dig +short element.rumpusroom.xyz || echo "[ERROR] Not configured"
	@echo ""
	@echo "Expected IP: $(SERVER_IP)"

# ============================================================================
# Terraform Infrastructure
# ============================================================================

tf-init: ## Initialize Terraform
	@cd $(TERRAFORM_DIR) && terraform init

tf-validate: ## Validate Terraform configuration
	@cd $(TERRAFORM_DIR) && terraform validate

tf-fmt: ## Format Terraform files
	@cd $(TERRAFORM_DIR) && terraform fmt -recursive

tf-plan: tf-validate ## Run Terraform plan
	@cd $(TERRAFORM_DIR) && terraform plan

tf-apply: tf-validate ## Deploy infrastructure
	@cd $(TERRAFORM_DIR) && terraform apply

tf-apply-auto: tf-validate ## Deploy infrastructure without confirmation
	@cd $(TERRAFORM_DIR) && terraform apply -auto-approve

tf-destroy: ## Destroy infrastructure (WARNING: Deletes everything!)
	@echo "[WARN] WARNING: This will destroy all infrastructure!"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform destroy

tf-output: ## Show Terraform outputs
	@cd $(TERRAFORM_DIR) && terraform output

# ============================================================================
# Server Management
# ============================================================================

ssh: ## SSH to the Matrix server
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "[ERROR] Infrastructure not deployed yet. Run 'make tf-apply' first"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP)

ssh-cmd: ## Run a command on server (usage: make ssh-cmd CMD="docker compose ps")
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "[ERROR] Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && $(CMD)"

logs: ## Show cloud-init logs on server
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "[ERROR] Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "sudo tail -f /var/log/cloud-init-output.log"

status-remote:
	@cd $(APP_DIR) && ./scripts/matrix-ctl status

status-local:
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "[ERROR] Infrastructure not deployed yet"; exit 1; fi
	@echo "Server IP: $(SERVER_IP)"
	@echo "--------------------------------------------------------"
	@$(SSH_RUN) -o ConnectTimeout=5 "cd $(APP_DIR) && ./scripts/matrix-ctl status" || echo "[ERROR] Cannot connect to server"

status: ## Check server and service status (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) status-remote; else $(MAKE) status-local; fi

status-json: ## Check server and service status formatted as JSON
	@if [ "$(IS_SERVER)" = "true" ]; then cd $(APP_DIR) && ./scripts/matrix-ctl status --json; else $(SSH_RUN) "cd $(APP_DIR) && ./scripts/matrix-ctl status --json"; fi

docker-logs-remote:
	@cd $(APP_DIR) && docker compose logs -f $(SERVICE)

docker-logs-local:
	@$(SSH_RUN) "cd $(APP_DIR) && docker compose logs -f $(SERVICE)"

docker-logs: ## Tail logs (auto-detects local vs server, SERVICE=synapse)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) docker-logs-remote SERVICE=$(SERVICE); else $(MAKE) docker-logs-local SERVICE=$(SERVICE); fi

docker-ps: ## Show running containers (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then cd $(APP_DIR) && docker compose ps; else $(SSH_RUN) "cd $(APP_DIR) && docker compose ps"; fi

docker-restart: ## Restart a service (auto-detects local vs server, SERVICE=nginx)
	@if [ "$(IS_SERVER)" = "true" ]; then cd $(APP_DIR) && docker compose restart $(SERVICE); else $(SSH_RUN) "cd $(APP_DIR) && docker compose restart $(SERVICE)"; fi

docker-up: ## Start / update containers (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then cd $(APP_DIR) && docker compose up -d --remove-orphans; else $(SSH_RUN) "cd $(APP_DIR) && docker compose up -d --remove-orphans"; fi

# ============================================================================
# User Management & Tokens
# ============================================================================

create-admin: ## Create an admin user non-interactively (USER=username PASS=password)
	@if [ -z "$(USER)" ] || [ -z "$(PASS)" ]; then \
		echo "[ERROR] Usage: make create-admin USER=admin PASS=secret [EMAIL=admin@example.com]"; \
		exit 1; \
	fi
	@if [ "$(IS_SERVER)" = "true" ]; then \
		cd $(APP_DIR) && ./scripts/matrix-ctl create-admin --username "$(USER)" --password "$(PASS)" --email "$(EMAIL)"; \
	else \
		$(SSH_RUN) "cd $(APP_DIR) && ./scripts/matrix-ctl create-admin --username '$(USER)' --password '$(PASS)' --email '$(EMAIL)'"; \
	fi

token: ## Generate MAS registration token (DAYS=365)
	@if [ "$(IS_SERVER)" = "true" ]; then \
		cd $(APP_DIR) && ./scripts/matrix-ctl token --days $(or $(DAYS),365); \
	else \
		$(SSH_RUN) "cd $(APP_DIR) && ./scripts/matrix-ctl token --days $(or $(DAYS),365)"; \
	fi

registration-token: token ## Alias for token

# ============================================================================
# Backup & Maintenance
# ============================================================================

backup: ## Trigger a backup (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then /opt/matrix/app/scripts/backup.sh; else $(SSH_RUN) "/opt/matrix/app/scripts/backup.sh"; fi

restore: ## Restore from backup (TIME=20260301 optional)
	@if [ "$(IS_SERVER)" = "true" ]; then /opt/matrix/app/scripts/restore.sh $(TIME); else $(SSH_RUN_T) "/opt/matrix/app/scripts/restore.sh $(TIME)"; fi

list-backups: ## List available backups in OCI (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then /opt/matrix/app/scripts/restore.sh --list; else $(SSH_RUN) "/opt/matrix/app/scripts/restore.sh --list"; fi

# ============================================================================
# Testing, Linting & Verification
# ============================================================================

test: ## Run unit tests with uv and pytest
	@cd rageshake-webhook && uv run --extra dev pytest

lint: ## Lint and check formatting with ruff
	@cd rageshake-webhook && uv run --extra dev ruff check .

test-health: ## Test Matrix health endpoints
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "[ERROR] Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@echo "Testing health endpoints on server..."
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && ./scripts/matrix-ctl status"

test-federation: ## Test Matrix federation
	@echo "Testing Federation..."
	@curl -s "https://federationtester.matrix.org/api/report?server_name=matrix.rumpusroom.xyz" | jq '.'

test-matrix: ## Test Matrix backend endpoints
	@echo "Testing Matrix Backend (matrix.rumpusroom.xyz)..."
	@echo ""
	@echo "Client API Versions:"
	@curl -s https://matrix.rumpusroom.xyz/_matrix/client/versions | jq -r '.versions[0:3] | join(", ")' || echo "[ERROR] Failed"
	@echo ""
	@echo "Server Delegation (.well-known):"
	@curl -s https://matrix.rumpusroom.xyz/.well-known/matrix/server | jq '.' || echo "[ERROR] Failed"
	@echo ""
	@echo "Root Endpoint (MAS Auth Frontend):"
	@curl -I -s https://matrix.rumpusroom.xyz/ | head -1 || echo "[ERROR] Failed"

test-element: ## Test Element frontend
	@echo "Testing Element Frontend (element.rumpusroom.xyz)..."
	@echo ""
	@echo "HTTP Status:"
	@curl -I -s https://element.rumpusroom.xyz | head -1 || echo "[ERROR] Failed"
	@echo ""
	@echo "Content Type:"
	@curl -I -s https://element.rumpusroom.xyz | grep -i "content-type" || echo "[ERROR] Failed"

test-architecture: check-dns test-matrix test-element ## Complete architecture verification (DNS + endpoints)
	@echo "--------------------------------------------------------"
	@echo "[OK] Architecture verification complete"

# ============================================================================
# Security & VPN Management
# ============================================================================

harden-host: ## Apply host-level security hardening (Docker, sysctl, SSH, firewall)
	@if [ "$(IS_SERVER)" = "true" ]; then \
		./scripts/matrix-ctl harden-host; \
	elif [ "$(SERVER_IP)" != "not-deployed" ]; then \
		ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && ./scripts/matrix-ctl harden-host"; \
	else \
		echo "[ERROR] Server IP not available"; \
		exit 1; \
	fi

audit: ## Run Lynis security audit on host
	@if [ "$(IS_SERVER)" = "true" ]; then \
		./scripts/matrix-ctl audit; \
	elif [ "$(SERVER_IP)" != "not-deployed" ]; then \
		ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && ./scripts/matrix-ctl audit"; \
	else \
		echo "[ERROR] Server IP not available"; \
		exit 1; \
	fi

vpn-user: ## Create a new Headscale VPN user (make vpn-user USER=alice)
	@if [ -z "$(USER)" ]; then \
		echo "[ERROR] Please specify USER, e.g.: make vpn-user USER=alice"; \
		exit 1; \
	fi
	@if [ "$(IS_SERVER)" = "true" ]; then \
		./scripts/matrix-ctl vpn add-user $(USER); \
	else \
		ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && ./scripts/matrix-ctl vpn add-user $(USER)"; \
	fi

vpn-key: ## Generate reusable 365-day VPN auth key (make vpn-key USER=alice)
	@if [ -z "$(USER)" ]; then \
		echo "[ERROR] Please specify USER, e.g.: make vpn-key USER=alice"; \
		exit 1; \
	fi
	@if [ "$(IS_SERVER)" = "true" ]; then \
		./scripts/matrix-ctl vpn create-key $(USER); \
	else \
		ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && ./scripts/matrix-ctl vpn create-key $(USER)"; \
	fi

vpn-nodes: ## List connected Headscale VPN nodes
	@if [ "$(IS_SERVER)" = "true" ]; then \
		./scripts/matrix-ctl vpn list-nodes; \
	else \
		ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && ./scripts/matrix-ctl vpn list-nodes"; \
	fi

# ============================================================================
# Cleanup
# ============================================================================

clean: ## Clean local temporary files
	@rm -rf $(TERRAFORM_DIR)/.terraform
	@rm -f $(TERRAFORM_DIR)/.terraform.lock.hcl
	@rm -f $(TERRAFORM_DIR)/terraform.tfstate.backup
	@echo "[OK] Cleaned temporary files"