.PHONY: help update-ip deploy init-env setup-synapse server-setup tf-init tf-plan tf-apply tf-destroy ssh logs status clean

# Variables
TERRAFORM_DIR := infra
SERVER_IP := $(shell cd $(TERRAFORM_DIR) && terraform output -raw server_public_ip 2>/dev/null || echo "not-deployed")

# Detect whether we are running on the server or locally.
# IS_SERVER=true when the server's app directory exists (i.e. we are already SSH'd in).
IS_SERVER := $(shell [ -f /opt/matrix/app/docker-compose.yml ] && echo true || echo false)

# SSH helper — wraps a command with the right SSH invocation.
SSH_RUN  = ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP)
SSH_RUN_T = ssh -i ~/.ssh/id_ed25519 -t ubuntu@$(SERVER_IP)
APP_DIR  = /opt/matrix/app

help: ## Show this help message
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  Matrix Synapse - Makefile Commands                     ║"
	@echo "║  Production Architecture: Separated Backend & Frontend   ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Quick Start Commands:"
	@echo "  make update-ip          - Update your IP and apply to firewall"
	@echo "  make deploy             - Deploy files to server"
	@echo "  make server-setup       - Complete server-side setup (run on server)"
	@echo ""
	@echo "Architecture Commands:"
	@echo "  make check-dns          - Verify DNS for matrix.* and element.*"
	@echo "  make setup-ssl          - Setup SSL for both domains (on server)"
	@echo "  make test-architecture  - Complete verification of both domains"
	@echo "  make show-architecture  - Display architecture diagram"
	@echo ""
	@echo "All Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ============================================================================
# Local Development & Deployment
# ============================================================================

update-ip: ## Detect current IP and update terraform config
	@./scripts/update-ip.sh

deploy: ## Deploy files from local to server (rsync)
	@./scripts/deploy.sh

init-env: ## Generate .env file with secure secrets
	@./scripts/init-env.sh

generate-mas-config: ## Generate MAS config.yaml from template with actual secrets
	@./scripts/generate-mas-config.sh

generate-synapse-config: ## Generate Synapse custom.yaml from template
	@./scripts/generate-synapse-config.sh

generate-configs: generate-mas-config generate-synapse-config ## Generate all config files from templates

setup-mas-db-local: ## Create MAS database and user in local Postgres
	@echo "Creating MAS database and user locally..."
	@set -a && . .env && set +a && \
	docker compose exec postgres psql -U synapse -c "CREATE USER mas WITH PASSWORD '$$MAS_DB_PASSWORD';" 2>/dev/null || echo 'User may already exist' && \
	docker compose exec postgres psql -U synapse -c "CREATE DATABASE mas OWNER mas;" 2>/dev/null || echo 'Database may already exist' && \
	docker compose exec postgres psql -U synapse -c "GRANT ALL PRIVILEGES ON DATABASE mas TO mas;" && \
	echo '✓ MAS database ready'

mas-init-local: ## Initialize MAS database schema locally
	@echo "Initializing MAS database..."
	@set -a && . .env && set +a && \
	docker compose run --rm mas database migrate --config /config.yaml && \
	echo '✓ MAS database initialized'


mas-logs-local: ## Show MAS logs locally
	@docker compose logs -f mas

mas-status-local: ## Check MAS health locally
	@echo "MAS Health Check..."
	@curl -sf http://localhost:8090/health && echo '✓ MAS is healthy' || echo '❌ MAS is not responding'

deploy-env: ## Deploy local .env file to server
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@if [ ! -f .env ]; then \
		echo "❌ No .env file found locally. Run 'make init-env' first"; \
		exit 1; \
	fi
	@echo "Deploying .env file to server..."
	@rsync -avz -e "ssh -i ~/.ssh/id_ed25519" .env ubuntu@$(SERVER_IP):/opt/matrix/app/.env
	@echo "✓ .env file deployed"
	@echo "⚠️  Restart services to apply: make docker-up"

# ============================================================================
# Server-Side Setup (run these ON the server)
# ============================================================================

setup-synapse: ## Setup Synapse data directory with correct permissions
	@./scripts/setup-synapse.sh

server-setup: ## Complete orchestrated server setup (run on server)
	@./scripts/server-setup.sh

setup-ssl: ## Setup SSL certificates for matrix & element domains
	@./scripts/setup-ssl.sh

# ============================================================================
# DNS & Architecture
# ============================================================================

check-dns: ## Verify DNS configuration for both domains
	@echo "Checking DNS configuration..."
	@echo ""
	@echo "Matrix Backend (matrix.rumpusroom.xyz):"
	@dig +short matrix.rumpusroom.xyz || echo "❌ Not configured"
	@echo ""
	@echo "Element Frontend (element.rumpusroom.xyz):"
	@dig +short element.rumpusroom.xyz || echo "❌ Not configured"
	@echo ""
	@echo "Expected IP: $(SERVER_IP)"

show-architecture: ## Display architecture diagram
	@cat ARCHITECTURE.md | head -40

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
	@echo "⚠️  WARNING: This will destroy all infrastructure!"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform destroy

tf-output: ## Show Terraform outputs
	@cd $(TERRAFORM_DIR) && terraform output

# ============================================================================
# Server Management
# ============================================================================

ssh: ## SSH to the Matrix server
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet. Run 'make tf-apply' first"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP)

ssh-cmd: ## Run a command on server (usage: make ssh-cmd CMD="docker compose ps")
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && $(CMD)"

logs: ## Show cloud-init logs on server
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "sudo tail -f /var/log/cloud-init-output.log"

status-remote: ## [on server] Show container status directly
	@echo "Running on server — showing local container status:"
	@cd $(APP_DIR) && docker compose ps

status-local: ## [from local] Show server and container status via SSH
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@echo "Server IP: $(SERVER_IP)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(SSH_RUN) -o ConnectTimeout=5 "\
		echo '✓ SSH connection successful' && \
		echo '' && \
		echo 'Services:' && \
		cd $(APP_DIR) && docker compose ps" || echo "❌ Cannot connect to server"

status: ## Check server and service status (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) status-remote; else $(MAKE) status-local; fi

docker-logs-remote: ## [on server] Tail logs for a service (SERVICE=synapse)
	@cd $(APP_DIR) && docker compose logs -f $(SERVICE)

docker-logs-local: ## [from local] Tail logs via SSH (SERVICE=synapse)
	@$(SSH_RUN) "cd $(APP_DIR) && docker compose logs -f $(SERVICE)"

docker-logs: ## Tail logs (auto-detects local vs server, SERVICE=synapse)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) docker-logs-remote SERVICE=$(SERVICE); else $(MAKE) docker-logs-local SERVICE=$(SERVICE); fi

docker-ps-remote: ## [on server] Show running containers
	@cd $(APP_DIR) && docker compose ps

docker-ps-local: ## [from local] Show running containers via SSH
	@$(SSH_RUN) "cd $(APP_DIR) && docker compose ps"

docker-ps: ## Show running containers (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) docker-ps-remote; else $(MAKE) docker-ps-local; fi

docker-restart-remote: ## [on server] Restart a service (SERVICE=nginx)
	@cd $(APP_DIR) && docker compose restart $(SERVICE)

docker-restart-local: ## [from local] Restart a service via SSH (SERVICE=nginx)
	@$(SSH_RUN) "cd $(APP_DIR) && docker compose restart $(SERVICE)"

docker-restart: ## Restart a service (auto-detects local vs server, SERVICE=nginx)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) docker-restart-remote SERVICE=$(SERVICE); else $(MAKE) docker-restart-local SERVICE=$(SERVICE); fi

docker-up-remote: ## [on server] Start / update all containers
	@cd $(APP_DIR) && docker compose up -d --remove-orphans

docker-up-local: ## [from local] Start / update all containers via SSH
	@$(SSH_RUN) "cd $(APP_DIR) && docker compose up -d --remove-orphans"

docker-up: ## Start / update containers (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) docker-up-remote; else $(MAKE) docker-up-local; fi

# ============================================================================
# User Management
# ============================================================================

create-user-remote: ## [on server] Create a new Matrix user (interactive)
	@cd $(APP_DIR) && docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008

create-user-local: ## [from local] Create a new Matrix user via SSH (interactive)
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@$(SSH_RUN_T) "cd $(APP_DIR) && docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"

create-user: ## Create a new Matrix user (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) create-user-remote; else $(MAKE) create-user-local; fi

# ============================================================================
# Configuration Management
# ============================================================================

setup-synapse-config: ## Generate initial Synapse config (one-time setup)
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@echo "Generating Synapse homeserver.yaml..."
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "\
		cd /opt/matrix/app && \
		docker compose run --rm -v synapse_data:/data synapse generate && \
		echo '✓ Config generated. Custom overrides are in config/custom.yaml'"

view-synapse-config: ## View current Synapse homeserver.yaml
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "cd /opt/matrix/app && docker compose exec synapse cat /data/homeserver.yaml" | less

edit-custom-config: ## Edit custom.yaml locally
	@$${EDITOR:-nano} config/custom.yaml

apply-config: ## Deploy and apply config changes
	@echo "Deploying config changes..."
	@$(MAKE) deploy
	@echo "Restarting Synapse..."
	@$(MAKE) docker-restart SERVICE=synapse
	@echo "✓ Config applied. Check logs with: make docker-logs SERVICE=synapse"

# ============================================================================
# Matrix Authentication Service (MAS) Management
# ============================================================================

setup-mas-db: ## Create MAS database and user in Postgres
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@echo "Creating MAS database and user..."
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "\
		cd /opt/matrix/app && \
		. .env && \
		docker compose exec postgres psql -U synapse -c \"CREATE USER mas WITH PASSWORD '\$$MAS_DB_PASSWORD';\" 2>/dev/null || echo 'User may already exist' && \
		docker compose exec postgres psql -U synapse -c \"CREATE DATABASE mas OWNER mas;\" 2>/dev/null || echo 'Database may already exist' && \
		docker compose exec postgres psql -U synapse -c \"GRANT ALL PRIVILEGES ON DATABASE mas TO mas;\" && \
		echo '✓ MAS database ready'"

mas-init: ## Initialize MAS database schema
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@echo "Initializing MAS database..."
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "\
		cd /opt/matrix/app && \
		export \$$(grep -v '^#' .env | xargs) && \
		docker compose run --rm mas database migrate --config /config.yaml && \
		echo '✓ MAS database initialized'"

mas-create-admin-remote: ## [on server] Create MAS admin user directly (interactive)
	@cd $(APP_DIR) && docker compose exec mas mas-cli manage register-user --admin

mas-create-admin-local: ## [from local] Create MAS admin user via SSH (interactive)
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@$(SSH_RUN_T) "cd $(APP_DIR) && docker compose exec mas mas-cli manage register-user --admin"

mas-create-admin: ## Create MAS admin user (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) mas-create-admin-remote; else $(MAKE) mas-create-admin-local; fi

mas-registration-token-remote: ## [on server] Generate registration token directly
	@cd $(APP_DIR) && python3 -c 'import subprocess, re; out = subprocess.run(["docker", "compose", "exec", "mas", "mas-cli", "--config", "/config.yaml", "manage", "issue-user-registration-token"], capture_output=True, text=True).stderr; print("Registration Token:", re.search(r"token:\s*(\w+)", out).group(1) if re.search(r"token:\s*(\w+)", out) else "Failed")'

mas-registration-token-local: ## [from local] Generate registration token via SSH
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@$(SSH_RUN) "cd $(APP_DIR) && python3 -c 'import subprocess, re; out = subprocess.run([\"docker\", \"compose\", \"exec\", \"mas\", \"mas-cli\", \"--config\", \"/config.yaml\", \"manage\", \"issue-user-registration-token\"], capture_output=True, text=True).stderr; print(\"Registration Token:\", re.search(r\"token:\s*(\w+)\", out).group(1) if re.search(r\"token:\s*(\w+)\", out) else \"Failed\")'"

registration-token: ## Generate MAS registration token (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) mas-registration-token-remote; else $(MAKE) mas-registration-token-local; fi

mas-logs: ## Show MAS logs
	@$(MAKE) docker-logs SERVICE=mas

mas-status: ## Check MAS health
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@echo "MAS Health Check..."
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "\
		curl -sf http://localhost:8090/health && echo '✓ MAS is healthy' || echo '❌ MAS is not responding'"

# ============================================================================
# Backup & Maintenance
# ============================================================================

backup-remote: ## [on server] Trigger backup directly
	@/opt/matrix/app/scripts/backup.sh

backup-local: ## [from local] Trigger backup via SSH
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@$(SSH_RUN) "/opt/matrix/app/scripts/backup.sh"

backup: ## Trigger a backup (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) backup-remote; else $(MAKE) backup-local; fi

restore-remote: ## [on server] Restore from backup directly (TIME=YYYYMMDD optional)
	@/opt/matrix/app/scripts/restore.sh $(TIME)

restore-local: ## [from local] Restore from backup via SSH (TIME=YYYYMMDD optional)
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@$(SSH_RUN_T) "/opt/matrix/app/scripts/restore.sh $(TIME)"

restore: ## Restore from backup (auto-detects local vs server, TIME=20260301 optional)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) restore-remote TIME=$(TIME); else $(MAKE) restore-local TIME=$(TIME); fi

list-backups-remote: ## [on server] List available backups
	@/opt/matrix/app/scripts/restore.sh --list

list-backups-local: ## [from local] List available backups via SSH
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then echo "❌ Infrastructure not deployed yet"; exit 1; fi
	@$(SSH_RUN) "/opt/matrix/app/scripts/restore.sh --list"

list-backups: ## List available backups in OCI (auto-detects local vs server)
	@if [ "$(IS_SERVER)" = "true" ]; then $(MAKE) list-backups-remote; else $(MAKE) list-backups-local; fi

# ============================================================================
# Testing & Verification
# ============================================================================

test-health: ## Test Matrix health endpoints
	@if [ "$(SERVER_IP)" = "not-deployed" ]; then \
		echo "❌ Infrastructure not deployed yet"; \
		exit 1; \
	fi
	@echo "Testing health endpoints..."
	@ssh -i ~/.ssh/id_ed25519 ubuntu@$(SERVER_IP) "\
		echo 'Synapse Health:' && \
		curl -sf http://localhost:8008/health || echo '❌ Failed' && \
		echo '' && \
		echo 'Matrix Client API:' && \
		curl -sf https://matrix.rumpusroom.xyz/_matrix/client/versions | jq -r '.versions[0:3] | join(\", \")' || echo '❌ Failed'"

test-federation: ## Test Matrix federation
	@echo "Testing Federation..."
	@curl -s "https://federationtester.matrix.org/api/report?server_name=matrix.rumpusroom.xyz" | jq '.'

test-https: ## Test HTTPS connectivity
	@echo "Testing HTTPS..."
	@curl -I https://matrix.rumpusroom.xyz

test-matrix: ## Test Matrix backend endpoints
	@echo "Testing Matrix Backend (matrix.rumpusroom.xyz)..."
	@echo ""
	@echo "Client API Versions:"
	@curl -s https://matrix.rumpusroom.xyz/_matrix/client/versions | jq -r '.versions[0:3] | join(", ")' || echo "❌ Failed"
	@echo ""
	@echo "Server Delegation (.well-known):"
	@curl -s https://matrix.rumpusroom.xyz/.well-known/matrix/server | jq '.' || echo "❌ Failed"
	@echo ""
	@echo "Root Endpoint:"
	@curl -s https://matrix.rumpusroom.xyz/ | jq '.' || echo "❌ Failed"

test-element: ## Test Element frontend
	@echo "Testing Element Frontend (element.rumpusroom.xyz)..."
	@echo ""
	@echo "HTTP Status:"
	@curl -I -s https://element.rumpusroom.xyz | head -1 || echo "❌ Failed"
	@echo ""
	@echo "Content Type:"
	@curl -I -s https://element.rumpusroom.xyz | grep -i "content-type" || echo "❌ Failed"

test-architecture: ## Complete architecture verification (DNS + endpoints)
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Testing Production Architecture"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@$(MAKE) check-dns
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(MAKE) test-matrix
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(MAKE) test-element
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "✓ Architecture verification complete"

# ============================================================================
# Cleanup & Utilities
# ============================================================================

clean: ## Clean local temporary files
	@rm -rf $(TERRAFORM_DIR)/.terraform
	@rm -f $(TERRAFORM_DIR)/.terraform.lock.hcl
	@rm -f $(TERRAFORM_DIR)/terraform.tfstate.backup
	@echo "✓ Cleaned temporary files"

clean-archive: ## Remove .archive directory
	@rm -rf .archive
	@echo "✓ Removed .archive directory"

view-config: ## View current configuration
	@echo "Terraform Variables:"
	@grep -v "^#" $(TERRAFORM_DIR)/terraform.tfvars | grep -v "^$$" || echo "Not configured"
	@echo ""
	@echo "Environment:"
	@if [ -f .env ]; then \
		grep -v "PASSWORD\|SECRET" .env || echo ".env configured"; \
	else \
		echo ".env not found"; \
	fi

# ============================================================================
# Full Deployment Workflow
# ============================================================================

full-deploy: ## Complete deployment from scratch
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  Full Matrix Deployment Workflow                         ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "This will:"
	@echo "  1. Update your IP address"
	@echo "  2. Deploy infrastructure"
	@echo "  3. Deploy application files"
	@echo ""
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo ""
	@echo "Step 1: Updating IP..."
	@$(MAKE) update-ip
	@echo ""
	@echo "Step 2: Deploying infrastructure..."
	@$(MAKE) tf-apply-auto
	@echo ""
	@echo "Waiting for cloud-init to complete (60 seconds)..."
	@sleep 60
	@echo ""
	@echo "Step 3: Deploying files..."
	@$(MAKE) deploy
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  Infrastructure Ready!                                   ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Next steps on the SERVER:"
	@echo "  1. SSH to server: make ssh"
	@echo "  2. Run setup: cd /opt/matrix/app && ./scripts/server-setup.sh"
	@echo "  3. Create user: make create-user"
	@echo ""

scan:
	@echo "Running Trivy securty scan..."
	docker run --rm -v $(PWD):/PWD -w /PWD aquasec/trivy:latest config .

lint:
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    	goodwithtech/dockle:latest matrixdotorg/synapse:v1.147.1

chekov:
	docker run --tty --volume $PWD:/tf --workdir /tf \
    	bridgecrew/checkov --directory /tf

ping:
	ping -c 3 $(SERVER_IP)