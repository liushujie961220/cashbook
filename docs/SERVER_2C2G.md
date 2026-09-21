# 2C / 2G / 40G Server Profile

This is the deployment profile for the user's small VPS.

## Why SQLite is enough

The instance is for two people, so V0.1 does not need PostgreSQL, Redis, a queue or a separate object database.

BeeCount Cloud upstream is designed to run as one Docker container with a persistent `/data` volume.

## Memory budget

Target:

| Component | Budget |
|---|---:|
| Cashbook Cloud | <= 1.1 GB |
| OS + Docker | ~500-650 MB |
| Reverse proxy / networking | < 150 MB |
| Safety margin | remaining |

The compose file caps the Cashbook container at 1.1 GB and 1.5 CPU.

## Disk budget

40 GB is sufficient for structured transactions and ordinary receipt attachments for two users.

Recommended split conceptually:

- OS/Docker/images: 10-15 GB
- live Cashbook data: several GB
- local rotating backups: several GB
- leave free space for upgrades

Do not let local backups grow without retention.

## Network exposure

Default compose binding is:

`127.0.0.1:8869:8080`

This intentionally prevents direct public access.

Preferred remote-access choices:

1. HTTPS reverse proxy with a domain and valid certificate.
2. Private overlay network such as Tailscale/WireGuard.

Avoid leaving plain HTTP port 8869 open to the Internet.

## First deployment

```bash
git clone <cashbook repository>
cd cashbook
bash scripts/server-init.sh

# Edit deploy/.env and set BOOTSTRAP_ADMIN_EMAIL.
cd deploy
docker compose --env-file .env up -d
docker compose logs -f cashbook-cloud
```

Before putting real financial data into the service:

- configure HTTPS/private network;
- create the second user;
- verify shared ledger;
- run `bash scripts/backup.sh`;
- perform one restore rehearsal.
