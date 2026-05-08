# CorePulse

**Enterprise Infrastructure Monitoring Platform**

CorePulse is a production-grade, open-source infrastructure monitoring platform built for modern data centers. It monitors Proxmox clusters, IBM FlashSystem arrays, Juniper/Cisco switches, VMs, and containers — delivering real-time metrics, historical analysis, intelligent alerting, and NOC-ready dashboards.

---

## Quick Start

```bash
# Clone
git clone https://github.com/your-org/corepulse.git
cd corepulse

# Generate SSL + configure
make gen-ssl
cp .env.example .env
# Edit .env — at minimum set SECRET_KEY and POSTGRES_PASSWORD

# Start
make up

# Run migrations
make migrate

# Access
open https://localhost
# Default: admin / corepulse
```

---

## What It Monitors

| Category | Targets |
|---|---|
| **Virtualization** | Proxmox VE clusters, nodes, VMs (QEMU), containers (LXC), HA |
| **Storage** | IBM FlashSystem 9100 — pools, volumes, IOPS, latency, capacity |
| **Network** | Juniper switches, Cisco SG300, Cisco Catalyst — ports, errors, LLDP/CDP |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         NGINX                               │
│              (TLS termination, rate limiting)               │
└───────────────┬────────────────────────┬───────────────────┘
                │                        │
    ┌───────────▼──────┐    ┌───────────▼──────┐
    │   FastAPI (API)   │    │  Next.js Frontend │
    │  - REST API       │    │  - Dashboard UI   │
    │  - WebSocket hub  │    │  - React + Charts │
    │  - RBAC/JWT auth  │    │  - TanStack Query │
    └───────────┬───────┘    └──────────────────┘
                │
    ┌───────────▼──────────────────────────────┐
    │            Redis                          │
    │  - Celery broker    - Pub/Sub for WS      │
    │  - Cache layer      - Rate limit state    │
    └───────────┬──────────────────────────────┘
                │
    ┌───────────▼──────────────────────────────┐
    │         Celery Workers                    │
    │  - Proxmox polling  - SNMP polling        │
    │  - FlashSystem poll - Alert evaluation    │
    │  - Health sweep     - Discovery scan      │
    └───────────┬──────────────────────────────┘
                │
    ┌───────────▼──────────────────────────────┐
    │    PostgreSQL + TimescaleDB               │
    │  - Metric hypertables (4h chunks)         │
    │  - Compression (7d)  - Retention (90d)    │
    │  - Continuous aggregates (1m)             │
    └──────────────────────────────────────────┘
```

---

## Tech Stack

**Backend:** Python 3.12 · FastAPI · SQLAlchemy 2 · Alembic · Celery · pysnmp · aiohttp

**Frontend:** Next.js 15 · React 19 · TypeScript · TailwindCSS · ECharts · Zustand · TanStack Query

**Database:** PostgreSQL 16 · TimescaleDB

**Infrastructure:** Docker · Docker Compose · NGINX · Redis 7

---

## Features

- **Real-time monitoring** via WebSocket with Redis pub/sub fan-out
- **SNMP v2c/v3** with bulk-walk, 64-bit counters, vendor drivers
- **Proxmox API** collection with parallel async polling
- **FlashSystem REST** integration with pool/volume/node stats
- **Alerting engine** with threshold, cooldown, deduplication, multi-channel dispatch
- **Dashboard engine** with drag/drop grid, widget persistence, shared dashboards
- **RBAC** with 4 roles: viewer / operator / engineer / admin
- **Audit logging** for all API mutations
- **NOC mode** — full-screen dashboard view for operations centres

---

## Default Credentials

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `corepulse` |

**Change immediately in production.**

---

## Configuration

All configuration is via environment variables. See `.env.example` for full reference.

Key variables:

```bash
SECRET_KEY=          # Required. Generate: openssl rand -hex 32
POSTGRES_PASSWORD=   # Required. Strong password for PostgreSQL
DATABASE_URL=        # Auto-constructed from POSTGRES_PASSWORD
REDIS_URL=           # Default: redis://redis:6379/0

# Notifications
SMTP_HOST=
SLACK_DEFAULT_WEBHOOK_URL=
TELEGRAM_BOT_TOKEN=
```

---

## API Documentation

Available at `https://localhost/api/docs` (disabled in production by default).

Base URL: `/api/v1`

Key endpoints:

| Method | Path | Description |
|---|---|---|
| POST | `/auth/login` | Get JWT tokens |
| GET | `/devices` | List all devices |
| POST | `/devices` | Add a device |
| POST | `/devices/{id}/poll` | Trigger immediate poll |
| POST | `/metrics/query` | Query time-series data |
| GET | `/alerts/incidents` | List alert incidents |
| POST | `/alerts/incidents/{id}/acknowledge` | Acknowledge alert |
| GET | `/dashboards` | List dashboards |
| WS | `/ws?token={jwt}` | Real-time WebSocket stream |

---

## Adding Devices

### Proxmox Cluster

```bash
curl -X POST https://localhost/api/v1/devices \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pve-cluster",
    "device_type": "proxmox_cluster",
    "host": "192.168.1.10",
    "port": 8006,
    "credential_profile_id": "<credential-uuid>"
  }'
```

### Proxmox Credentials

```bash
curl -X POST https://localhost/api/v1/devices/credentials \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "PVE API Token",
    "protocol": "api_token",
    "credentials": {
      "token_id": "root@pam!monitoring",
      "token_secret": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }
  }'
```

### SNMP Device (Juniper)

```bash
curl -X POST https://localhost/api/v1/devices \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "core-switch-1",
    "device_type": "juniper_switch",
    "host": "10.0.0.1",
    "credential_profile_id": "<snmp-cred-uuid>"
  }'
```

---

## Alert Rules

```bash
# CPU > 90% for any node
curl -X POST https://localhost/api/v1/alerts/rules \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "Node CPU Critical",
    "metric": "cpu.util",
    "device_type_filter": "proxmox_node",
    "condition_type": "threshold",
    "condition_config": {"operator": ">", "threshold": 90},
    "severity": "critical",
    "cooldown_seconds": 300
  }'
```

---

## Deployment

See [docs/deployment.md](docs/deployment.md) for full production deployment guide.

Quick production checklist:

- [ ] Change `SECRET_KEY` to a strong random value (`openssl rand -hex 32`)
- [ ] Change `POSTGRES_PASSWORD`
- [ ] Configure real SSL certificates (replace self-signed)
- [ ] Set `ALLOWED_ORIGINS` to your domain
- [ ] Configure SMTP for email alerts
- [ ] Set up backup cron: `0 2 * * * /opt/corepulse/scripts/backup.sh`
- [ ] Change default admin password

---

## Backup & Restore

```bash
# Backup
make backup

# Restore
make restore FILE=backups/corepulse_20250101_020000.sql.gz
```

Backups are stored in `./backups/` and automatically pruned after 30 days.

---

## Development

```bash
# Install backend deps
cd backend && pip install -r requirements.txt

# Install frontend deps
cd frontend && npm install

# Run dev stack (postgres + redis via docker, app locally)
make dev-backend   # terminal 1
make dev-frontend  # terminal 2
make dev-worker    # terminal 3
make dev-beat      # terminal 4
```

---

## Project Structure

```
CorePulse/
├── backend/
│   ├── app/
│   │   ├── core/           # Config, database, redis, security, exceptions
│   │   ├── models/         # SQLAlchemy ORM models + Pydantic schemas
│   │   ├── services/       # Business logic (metrics, devices)
│   │   ├── collectors/     # Proxmox, SNMP, FlashSystem polling engines
│   │   ├── alerting/       # Alert evaluation + notification dispatch
│   │   ├── workers/        # Celery tasks and app factory
│   │   ├── websocket/      # WebSocket hub with Redis fan-out
│   │   ├── api/v1/         # REST API endpoints
│   │   └── main.py         # FastAPI app factory
│   ├── alembic/            # Database migrations
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   ├── src/
│   │   ├── app/            # Next.js App Router pages
│   │   ├── components/     # React components (layout, widgets, charts)
│   │   ├── lib/            # API client, Zustand stores, React Query hooks
│   │   └── types/          # TypeScript type definitions
│   ├── package.json
│   └── Dockerfile
├── deployments/
│   ├── nginx/              # NGINX configuration
│   ├── scripts/            # DB init scripts
│   └── kubernetes/         # (Future) K8s manifests
├── scripts/                # Backup, restore, utility scripts
├── .github/workflows/      # GitHub Actions CI/CD
├── docker-compose.yml
├── Makefile
└── .env.example
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Support

- Documentation: [docs/](docs/)
- Issues: GitHub Issues
- Architecture: [docs/architecture.md](docs/architecture.md)
