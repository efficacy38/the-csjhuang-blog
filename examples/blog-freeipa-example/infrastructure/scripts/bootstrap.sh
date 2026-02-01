#!/bin/bash
# FreeIPA Bootstrap Script - Blog Example
# Deploys a FreeIPA server with custom LDAP schema for demonstration
#
# Usage: bash scripts/bootstrap.sh
#
# Related blog posts:
#   - FreeIPA 權限系統
#   - FreeIPA 集中式 Sudo 管理
#   - FreeIPA 與 NFS 整合

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment variables
if [ -f "$POC_ROOT/.env" ]; then
	set -a && source "$POC_ROOT/.env" && set +a
fi

# Configuration
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-freeipa-demo}"
FREEIPA_CONTAINER="${PROJECT_NAME}-freeipa-server-1"
FREEIPA_DATA_VOLUME="${PROJECT_NAME}_freeipa-data"
NETWORK_NAME="${PROJECT_NAME}_ldap-network"
ADMIN_PASSWORD="${FREEIPA_ADMIN_PASSWORD:-AdminPass123!}"

# Logging
log() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[OK]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

echo -e "\033[0;34m=== FreeIPA Demo Bootstrap ===\033[0m"
echo "This script deploys a FreeIPA server for blog demonstration"
echo ""

# Utility functions
container_running() {
	docker ps --format '{{.Names}}' | grep -q "^$1$"
}

wait_for_container() {
	local container=$1 max_attempts=$2 check_command=$3
	log "Waiting for $container to be ready (max ${max_attempts}s)..."

	for ((i = 1; i <= max_attempts; i++)); do
		if eval "$check_command" >/dev/null 2>&1; then
			success "$container is ready!"
			return 0
		fi
		[ $i -eq $max_attempts ] && {
			error "$container failed to become ready"
			return 1
		}
		echo -n "."
		sleep 1
	done
}

check_freeipa_health() {
	local container=$1 admin_password=$2

	# Check 1: Container is running
	if ! container_running $container; then
		return 1
	fi

	# Check 2: IPA service is active
	if ! docker exec $container systemctl is-active --quiet ipa 2>/dev/null; then
		return 1
	fi

	# Check 3: LDAP port is responding
	if ! docker exec $container timeout 5 bash -c "echo > /dev/tcp/localhost/389" 2>/dev/null; then
		return 1
	fi

	# Check 4: Admin authentication works
	if ! docker exec $container bash -c "echo '$admin_password' | kinit admin" >/dev/null 2>&1; then
		return 1
	fi

	# Check 5: IPA commands respond
	if ! docker exec $container ipa user-find --sizelimit=1 >/dev/null 2>&1; then
		return 1
	fi

	return 0
}

cleanup_existing() {
	log "Cleaning up existing containers..."

	# Stop docker-compose services
	cd "$POC_ROOT" && docker compose -p "$PROJECT_NAME" down --remove-orphans 2>/dev/null || true

	# Stop FreeIPA (not managed by docker-compose)
	if docker ps -a --format '{{.Names}}' | grep -q "^$FREEIPA_CONTAINER$"; then
		docker stop $FREEIPA_CONTAINER >/dev/null 2>&1 || true
		docker rm $FREEIPA_CONTAINER >/dev/null 2>&1 || true
	fi
}

check_prerequisites() {
	log "Checking prerequisites..."
	command -v docker &>/dev/null || {
		error "Docker not installed"
		exit 1
	}

	[ ! -f /sys/fs/cgroup/cgroup.controllers ] && warning "cgroups v2 not detected. FreeIPA may fail to start."

	for port in 80 389 443 636 88 464 8080 8090 5432; do
		netstat -tuln 2>/dev/null | grep -q ":$port " && warning "Port $port appears to be in use"
	done
	success "Prerequisites check completed"
}

prepare_environment() {
	log "Preparing environment..."

	# Create FreeIPA data volume if it doesn't exist
	if ! docker volume inspect "$FREEIPA_DATA_VOLUME" >/dev/null 2>&1; then
		docker volume create "$FREEIPA_DATA_VOLUME" >/dev/null
		log "Created Docker volume: $FREEIPA_DATA_VOLUME"
	else
		log "Docker volume $FREEIPA_DATA_VOLUME already exists"
	fi

	for dir in config/keycloak config/webapp config/freeipa; do
		[ ! -d "$POC_ROOT/$dir" ] && warning "Configuration directory $POC_ROOT/$dir not found"
	done
	success "Environment prepared"
}

start_freeipa() {
	log "Starting FreeIPA Server..."
	warning "This process takes 10-15 minutes for initial installation..."

	# FreeIPA requires special Docker options not available in docker-compose
	# Note: No port mappings to host - services accessible only within docker network
	docker run -d --name $FREEIPA_CONTAINER \
		-h ipa.lab.example.com --read-only \
		--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
		-v "$FREEIPA_DATA_VOLUME:/data" \
		--network "$NETWORK_NAME" \
		--expose 80 --expose 443 --expose 389 --expose 636 --expose 88 --expose 464 \
		-e PASSWORD=$ADMIN_PASSWORD \
		freeipa/freeipa-server:almalinux-10 \
		ipa-server-install -U -r LAB.EXAMPLE.COM --no-ntp --skip-mem-check

	# Monitor installation with comprehensive health checks
	local start_time=$(date +%s) timeout=1200
	log "Monitoring FreeIPA installation with health checks..."

	while true; do
		local elapsed=$(($(date +%s) - start_time))

		if [ $elapsed -gt $timeout ]; then
			error "FreeIPA installation timeout after ${timeout}s"
			docker logs $FREEIPA_CONTAINER --tail 50
			return 1
		fi

		# Check if container exited unexpectedly
		if ! container_running $FREEIPA_CONTAINER; then
			error "FreeIPA container exited unexpectedly"
			docker logs $FREEIPA_CONTAINER --tail 50
			return 1
		fi

		# Perform comprehensive health check
		if check_freeipa_health $FREEIPA_CONTAINER "$ADMIN_PASSWORD"; then
			success "FreeIPA installation completed and all health checks passed"
			log "Health checks: Container running, IPA service active, LDAP responding, Admin auth OK, IPA commands functional"
			return 0
		fi

		# Progress reporting every 30 seconds
		[ $((elapsed % 30)) -eq 0 ] && log "Installation progress: ${elapsed}s elapsed (still waiting for health checks to pass)"
		sleep 10
	done
}

start_services() {
	log "Starting supporting services (PostgreSQL, NFS)..."
	cd "$POC_ROOT" && docker compose -p "$PROJECT_NAME" up -d
	success "Supporting services started"
}

install_custom_schema() {
	# Custom schema is optional - skip if file doesn't exist
	local schema_src="$POC_ROOT/config/freeipa/99cs-custom.ldif"

	if [ ! -f "$schema_src" ]; then
		log "Custom schema file not found, skipping (this is optional)"
		return 0
	fi

	log "Installing custom LDAP schema..."
	local schema_dst="/etc/dirsrv/slapd-LAB-EXAMPLE-COM/schema/99cs-custom.ldif"

	docker cp "$schema_src" "$FREEIPA_CONTAINER:$schema_dst"

	if [ $? -eq 0 ]; then
		success "Custom schema file created"
	else
		warning "Failed to create custom schema file (continuing anyway)"
		return 0
	fi

	# Restart Directory Server to load the new schema
	log "Restarting Directory Server to load custom schema..."
	docker exec $FREEIPA_CONTAINER systemctl restart dirsrv@LAB-EXAMPLE-COM
	sleep 5
	success "Custom schema installed"
}

populate_test_data() {
	log "Populating FreeIPA with test data..."
	if [ -f "$SCRIPT_DIR/seed-data.sh" ]; then
		bash "$SCRIPT_DIR/seed-data.sh"
		success "Test data populated successfully"
	else
		warning "Test data script not found. Skipping user population."
	fi
}

verify_deployment() {
	log "Verifying deployment..."
	echo -e "\n=== Service Status ==="
	docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(${PROJECT_NAME})" || true

	echo -e "\n=== FreeIPA Verification ==="
	if docker exec $FREEIPA_CONTAINER bash -c "echo '$ADMIN_PASSWORD' | kinit admin >/dev/null 2>&1 && ipa user-find --sizelimit=0" | grep "Number of entries returned"; then
		success "FreeIPA is functional"
	else
		error "FreeIPA verification failed"
	fi

	echo -e "\n=== Access Info ==="
	echo "FreeIPA: ipa.lab.example.com (admin / $ADMIN_PASSWORD)"
	echo "Network: $NETWORK_NAME"
	success "Deployment complete!"
}

main() {
	echo
	read -p "Deploy FreeIPA demo environment? (y/N): " -n 1 -r
	echo
	[[ ! $REPLY =~ ^[Yy]$ ]] && { log "Cancelled"; exit 0; }

	check_prerequisites
	cleanup_existing
	prepare_environment

	docker network create "$NETWORK_NAME" 2>/dev/null || true

	start_freeipa
	install_custom_schema
	start_services
	populate_test_data
	verify_deployment

	echo
	success "FreeIPA Demo Ready!"
	echo -e "\nNext steps:"
	echo "1. Connect to FreeIPA: docker exec -it $FREEIPA_CONTAINER bash"
	echo "2. Authenticate: kinit admin"
	echo "3. Try commands: ipa user-find, ipa group-find"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
