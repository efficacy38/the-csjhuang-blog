# FreeIPA Demo Environment

Example code for the FreeIPA blog series at [blog.csjhuang.net](https://blog.csjhuang.net).

## Related Articles

- [FreeIPA 權限系統：從 Group 到 RBAC 完整指南](/posts/freeipa-permission-system)
- [FreeIPA 集中式 Sudo 管理：hostgroup 與 netgroup 實戰](/posts/freeipa-sudo-hostgroup)
- [FreeIPA 與 NFS 整合：Kerberized 家目錄共享完整指南](/posts/freeipa-nfs-kerberos)

## Prerequisites

- Docker with cgroups v2 support
- [just](https://github.com/casey/just) command runner (optional)

## Quick Start

```bash
# Copy environment file
cp infrastructure/.env.example infrastructure/.env

# Deploy FreeIPA (takes 10-15 minutes for initial setup)
just up
# or: bash infrastructure/scripts/bootstrap.sh

# Connect to FreeIPA
just shell
# or: docker exec -it freeipa-demo-freeipa-server-1 bash

# Inside FreeIPA container:
kinit admin        # Password: AdminPass123!
ipa user-find
ipa group-find
```

## Commands

| Command | Description |
|---------|-------------|
| `just up` | Deploy FreeIPA environment |
| `just down` | Stop containers (preserves data) |
| `just destroy` | Remove everything |
| `just shell` | Connect to FreeIPA container |
| `just status` | Show container status |
| `just seed` | Populate test users/groups |
| `just logs` | View FreeIPA logs |

## Directory Structure

```
infrastructure/
├── .env.example          # Environment variables template
├── docker-compose.yml    # Supporting services (NFS)
├── config/
│   └── nfs/              # NFS exports configuration
└── scripts/
    ├── bootstrap.sh      # Main deployment script
    ├── seed-data.sh      # Test data population
    └── cleanup.sh        # Environment cleanup
```

## Test Data

After running `just seed`, the following entities are created:

**Users:** (password: `password123`)
- `alice` - Developer (frontend team)
- `bob` - Developer (backend team)
- `carol` - Helpdesk (tier1-support)
- `dave` - DBA (database administrator)

**Groups:**
- POSIX: `developers`, `dbas`, `sysadmins`, `engineering`, `frontend`, `backend`
- Non-POSIX: `tier1-support`
- Nested: `engineering` contains `frontend` and `backend`

**Hostgroups:**
- `webservers`, `dbservers` - Server types
- `production`, `staging` - Environments
- `all-servers` - Contains `webservers` and `dbservers`

**Sudo Rules:**
- `dba-postgresql` - DBAs can manage PostgreSQL on dbservers
- `developers-docker` - Developers can use Docker everywhere

**RBAC:**
- `Password Reset Operator` role assigned to `tier1-support` group

## Cleanup

```bash
# Stop containers (preserves data for restart)
just down

# Remove everything (containers, volumes, networks)
just destroy
```
