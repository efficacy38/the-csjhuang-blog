#!/bin/bash
# Environment Cleanup Script for NCTU CS LDAP Migration POC
# Usage: bash scripts/cleanup-environment.sh
#
# Supports parallel testing: set COMPOSE_PROJECT_NAME to clean specific project

set -e

# Support parallel testing with dynamic naming
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-infrastructure}"
CONTAINERS=("${PROJECT_NAME}-freeipa-server-1" "${PROJECT_NAME}-keycloak-1" "${PROJECT_NAME}-keycloak-db-1" "${PROJECT_NAME}-nfs-server-1" "${PROJECT_NAME}-freeipa-client-1")
VOLUMES=("${PROJECT_NAME}_freeipa-data" "${PROJECT_NAME}_keycloak-db-data" "${PROJECT_NAME}_keycloak-import" "${PROJECT_NAME}_nfs-data")
NETWORK="${PROJECT_NAME}_ldap-network"

echo -e "\033[0;34m=== NCTU CS LDAP Migration POC Cleanup ===\033[0m"
echo "This script will remove ALL containers, volumes, and data from the POC environment"

# Logging functions
log() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

cleanup_containers() {
	log "Stopping and removing containers..."
	for container in "${CONTAINERS[@]}"; do
		if docker ps -a --format '{{.Names}}' | grep -q "^$container$"; then
			docker stop $container >/dev/null 2>&1 || true
			docker rm $container >/dev/null 2>&1 || true
			success "Removed: $container"
		fi
	done
}

cleanup_volumes() {
	log "Removing volumes..."
	for volume in "${VOLUMES[@]}"; do
		if docker volume ls --format '{{.Name}}' | grep -q "^$volume$"; then
			docker volume rm $volume >/dev/null 2>&1 || true
			success "Removed: $volume"
		fi
	done
}

cleanup_network() {
	log "Removing network..."
	if docker network ls --format '{{.Name}}' | grep -q "^$NETWORK$"; then
		docker network rm $NETWORK >/dev/null 2>&1 || true
		success "Removed: $NETWORK"
	fi
}

cleanup_dangling() {
	log "Cleaning up dangling resources..."
	dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null || true)
	[ -n "$dangling_images" ] && docker rmi $dangling_images >/dev/null 2>&1 || true
	docker network prune -f >/dev/null 2>&1 || true
	success "Cleaned up unused resources"
}

show_status() {
	log "Current Docker resource status (project: $PROJECT_NAME):"
	echo -e "\n=== Running Containers ==="
	docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(${PROJECT_NAME})" || echo "No POC containers running"

	echo -e "\n=== POC Volumes ==="
	docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | grep -E "(${PROJECT_NAME}_)" || echo "No POC volumes found"

	echo -e "\n=== POC Networks ==="
	docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | grep -E "(${PROJECT_NAME}_ldap-network)" || echo "No POC networks found"
}

main() {
	echo -e "\nCurrent status before cleanup:"
	show_status
	echo
	read -p "Are you sure you want to remove ALL POC resources? This cannot be undone! (y/N): " -n 1 -r
	echo
	[[ ! $REPLY =~ ^[Yy]$ ]] && {
		log "Cleanup cancelled by user"
		exit 0
	}

	echo
	warning "Starting cleanup process..."
	cleanup_containers
	cleanup_volumes
	cleanup_network
	cleanup_dangling

	echo
	success "🧹 Cleanup completed!"
	echo -e "\nFinal status:"
	show_status
	echo
	log "All POC resources have been removed."
	log "To redeploy, run: bash scripts/bootstrap-full-stack.sh"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
