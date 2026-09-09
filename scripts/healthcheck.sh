#!/bin/bash
# Matrix Server Health Check Script
# Run every 5 minutes via cron: */5 * * * * /opt/matrix/healthcheck.sh

set -euo pipefail

# shellcheck disable=SC2034
ALERT_EMAIL="your-email@example.com"  # Configure this
LOG_FILE="/var/log/matrix-health.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

alert() {
  log "ALERT: $1"
  # Implement your alerting (email, Slack, PagerDuty, etc.)
  # echo "$1" | mail -s "Matrix Server Alert" "${ALERT_EMAIL}"
}

# Check 1: Docker containers running
check_containers() {
  local services=("postgres" "synapse" "element" "coturn" "nginx")
  for service in "${services[@]}"; do
    if ! docker compose ps --services --filter "status=running" | grep -q "^${service}$"; then
      alert "Container ${service} is not running!"
      return 1
    fi
  done
  log "All containers running OK"
}

# Check 2: Synapse health endpoint
check_synapse_health() {
  if ! curl -sf http://localhost:8008/health > /dev/null; then
    alert "Synapse health check failed!"
    return 1
  fi
  log "Synapse health OK"
}

# Check 3: PostgreSQL connection
check_postgres() {
  if ! docker compose exec -T postgres pg_isready -U synapse > /dev/null; then
    alert "PostgreSQL is not ready!"
    return 1
  fi
  log "PostgreSQL OK"
}

# Check 4: Disk space (alert if >85%)
check_disk_space() {
  local usage
  usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
  if [ "${usage}" -gt 85 ]; then
    alert "Disk space critical: ${usage}% used!"
    return 1
  fi
  log "Disk space OK (${usage}%)"
}

# Check 5: Memory usage
check_memory() {
  local mem_used
  mem_used=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
  if [ "${mem_used}" -gt 90 ]; then
    alert "Memory usage critical: ${mem_used}%!"
    return 1
  fi
  log "Memory OK (${mem_used}%)"
}

# Run all checks
log "=== Starting health checks ==="
check_containers
check_synapse_health
check_postgres
check_disk_space
check_memory
log "=== All health checks passed ==="
