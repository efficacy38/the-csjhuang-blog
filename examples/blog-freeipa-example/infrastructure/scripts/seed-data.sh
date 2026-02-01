#!/bin/bash
# FreeIPA Test Data Population Script
# Creates users, groups, and hostgroups for blog demonstration
#
# Related blog posts:
#   - FreeIPA 權限系統：從 Group 到 RBAC 完整指南
#   - FreeIPA 集中式 Sudo 管理：hostgroup 與 netgroup 實戰
#   - FreeIPA 與 NFS 整合

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment
if [ -f "$POC_ROOT/.env" ]; then
	set -a && source "$POC_ROOT/.env" && set +a
fi

# Configuration
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-freeipa-demo}"
CONTAINER_NAME="${PROJECT_NAME}-freeipa-server-1"
ADMIN_PASSWORD="${FREEIPA_ADMIN_PASSWORD:-AdminPass123!}"
TEST_PASSWORD="${TEST_USER_PASSWORD:-password123}"

echo "=== FreeIPA Test Data Population ==="
echo "Creating entities for blog demonstration..."

# Helper functions
run_ipa() {
	docker exec -i $CONTAINER_NAME bash -c "echo '$ADMIN_PASSWORD' | kinit admin && $*"
}

wait_for_freeipa() {
	echo "Waiting for FreeIPA..."
	for i in {1..30}; do
		if docker exec $CONTAINER_NAME systemctl is-active --quiet ipa 2>/dev/null; then
			echo "FreeIPA is ready!"
			return 0
		fi
		sleep 5
	done
	echo "ERROR: FreeIPA not ready"
	return 1
}

create_user() {
	local username=$1 first=$2 last=$3 email=$4 groups=$5
	echo "  Creating user: $username"
	run_ipa "ipa user-add $username --first='$first' --last='$last' --email='$email'" 2>/dev/null || true
	echo "$TEST_PASSWORD" | docker exec -i $CONTAINER_NAME bash -c "echo '$ADMIN_PASSWORD' | kinit admin && ipa user-mod $username --password" 2>/dev/null || true
	docker exec $CONTAINER_NAME kadmin.local -q "modprinc -pwexpire never $username" 2>/dev/null || true
	for group in $groups; do
		run_ipa "ipa group-add-member $group --users=$username" 2>/dev/null || true
	done
}

wait_for_freeipa

# =============================================================================
# Groups (freeipa-005-permission-system.md)
# =============================================================================
echo ""
echo "=== Creating Groups ==="

# Department/role groups (POSIX)
run_ipa "ipa group-add developers --desc='Development Team'" 2>/dev/null || true
run_ipa "ipa group-add dbas --desc='Database Administrators'" 2>/dev/null || true
run_ipa "ipa group-add sysadmins --desc='System Administrators'" 2>/dev/null || true

# Nested group example: engineering contains frontend and backend
run_ipa "ipa group-add engineering --desc='Engineering Department'" 2>/dev/null || true
run_ipa "ipa group-add frontend --desc='Frontend Team'" 2>/dev/null || true
run_ipa "ipa group-add backend --desc='Backend Team'" 2>/dev/null || true
run_ipa "ipa group-add-member engineering --groups=frontend,backend" 2>/dev/null || true

# Non-POSIX groups for RBAC
run_ipa "ipa group-add tier1-support --desc='Tier 1 Support Team' --nonposix" 2>/dev/null || true

echo "  Groups created: developers, dbas, sysadmins, engineering, frontend, backend, tier1-support"

# =============================================================================
# Users (freeipa-005-permission-system.md)
# =============================================================================
echo ""
echo "=== Creating Users ==="

# Alice - developer (frontend)
create_user "alice" "Alice" "Chen" "alice@lab.example.com" "developers frontend"

# Bob - developer (backend)
create_user "bob" "Bob" "Wang" "bob@lab.example.com" "developers backend"

# Carol - helpdesk
create_user "carol" "Carol" "Lin" "carol@lab.example.com" "tier1-support"

# Dave - DBA
create_user "dave" "Dave" "Liu" "dave@lab.example.com" "dbas backend"

echo "  Users created: alice, bob, carol, dave"

# =============================================================================
# Hostgroups (freeipa-006-sudo-hostgroup.md)
# =============================================================================
echo ""
echo "=== Creating Hostgroups ==="

run_ipa "ipa hostgroup-add webservers --desc='Web Servers'" 2>/dev/null || true
run_ipa "ipa hostgroup-add dbservers --desc='Database Servers'" 2>/dev/null || true
run_ipa "ipa hostgroup-add production --desc='Production Environment'" 2>/dev/null || true
run_ipa "ipa hostgroup-add staging --desc='Staging Environment'" 2>/dev/null || true

# Nested hostgroup
run_ipa "ipa hostgroup-add all-servers --desc='All Servers'" 2>/dev/null || true
run_ipa "ipa hostgroup-add-member all-servers --hostgroups=webservers,dbservers" 2>/dev/null || true

echo "  Hostgroups created: webservers, dbservers, production, staging, all-servers"

# =============================================================================
# Sudo Commands and Rules (freeipa-006-sudo-hostgroup.md)
# =============================================================================
echo ""
echo "=== Creating Sudo Commands ==="

# PostgreSQL management commands
run_ipa "ipa sudocmd-add '/usr/bin/systemctl restart postgresql'" 2>/dev/null || true
run_ipa "ipa sudocmd-add '/usr/bin/systemctl stop postgresql'" 2>/dev/null || true
run_ipa "ipa sudocmd-add '/usr/bin/systemctl start postgresql'" 2>/dev/null || true
run_ipa "ipa sudocmd-add '/usr/bin/systemctl status postgresql'" 2>/dev/null || true

# Docker commands
run_ipa "ipa sudocmd-add '/usr/bin/docker'" 2>/dev/null || true
run_ipa "ipa sudocmd-add '/usr/bin/docker-compose'" 2>/dev/null || true

echo "  Sudo commands created"

echo ""
echo "=== Creating Sudo Command Groups ==="

run_ipa "ipa sudocmdgroup-add postgresql-management --desc='PostgreSQL Management Commands'" 2>/dev/null || true
run_ipa "ipa sudocmdgroup-add-member postgresql-management --sudocmds='/usr/bin/systemctl restart postgresql'" 2>/dev/null || true
run_ipa "ipa sudocmdgroup-add-member postgresql-management --sudocmds='/usr/bin/systemctl stop postgresql'" 2>/dev/null || true
run_ipa "ipa sudocmdgroup-add-member postgresql-management --sudocmds='/usr/bin/systemctl start postgresql'" 2>/dev/null || true
run_ipa "ipa sudocmdgroup-add-member postgresql-management --sudocmds='/usr/bin/systemctl status postgresql'" 2>/dev/null || true

run_ipa "ipa sudocmdgroup-add docker-commands --desc='Docker Commands'" 2>/dev/null || true
run_ipa "ipa sudocmdgroup-add-member docker-commands --sudocmds='/usr/bin/docker'" 2>/dev/null || true
run_ipa "ipa sudocmdgroup-add-member docker-commands --sudocmds='/usr/bin/docker-compose'" 2>/dev/null || true

echo "  Sudo command groups created: postgresql-management, docker-commands"

echo ""
echo "=== Creating Sudo Rules ==="

# DBA can manage PostgreSQL on dbservers
run_ipa "ipa sudorule-add dba-postgresql --desc='DBA can manage PostgreSQL'" 2>/dev/null || true
run_ipa "ipa sudorule-add-user dba-postgresql --groups=dbas" 2>/dev/null || true
run_ipa "ipa sudorule-add-host dba-postgresql --hostgroups=dbservers" 2>/dev/null || true
run_ipa "ipa sudorule-add-allow-command dba-postgresql --sudocmdgroups=postgresql-management" 2>/dev/null || true

# Developers can use docker on all hosts
run_ipa "ipa sudorule-add developers-docker --desc='Developers can use Docker'" 2>/dev/null || true
run_ipa "ipa sudorule-add-user developers-docker --groups=developers" 2>/dev/null || true
run_ipa "ipa sudorule-mod developers-docker --hostcategory=all" 2>/dev/null || true
run_ipa "ipa sudorule-add-allow-command developers-docker --sudocmdgroups=docker-commands" 2>/dev/null || true

echo "  Sudo rules created: dba-postgresql, developers-docker"

# =============================================================================
# RBAC Example (freeipa-005-permission-system.md)
# =============================================================================
echo ""
echo "=== Creating RBAC Example ==="

# Password Reset Operator role
run_ipa "ipa privilege-add 'Password Reset Only' --desc='Can only reset user passwords'" 2>/dev/null || true
run_ipa "ipa privilege-add-permission 'Password Reset Only' --permissions='System: Change User password'" 2>/dev/null || true

run_ipa "ipa role-add 'Password Reset Operator' --desc='Operator who can only reset passwords'" 2>/dev/null || true
run_ipa "ipa role-add-privilege 'Password Reset Operator' --privileges='Password Reset Only'" 2>/dev/null || true
run_ipa "ipa role-add-member 'Password Reset Operator' --groups=tier1-support" 2>/dev/null || true

echo "  RBAC: Password Reset Operator role assigned to tier1-support"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Test Data Population Complete!"
echo "=========================================="
echo ""
echo "Users (password: $TEST_PASSWORD):"
echo "  alice  - Developer (frontend)"
echo "  bob    - Developer (backend)"
echo "  carol  - Helpdesk (tier1-support)"
echo "  dave   - DBA"
echo ""
echo "Groups:"
echo "  POSIX: developers, dbas, sysadmins, engineering, frontend, backend"
echo "  Non-POSIX: tier1-support"
echo ""
echo "Hostgroups: webservers, dbservers, production, staging, all-servers"
echo ""
echo "Sudo Rules:"
echo "  dba-postgresql    - DBAs can manage PostgreSQL on dbservers"
echo "  developers-docker - Developers can use Docker everywhere"
echo ""
echo "RBAC:"
echo "  Password Reset Operator - carol can reset passwords"
echo ""
