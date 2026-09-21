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
- perform one restore rehearsal with `bash scripts/restore.sh <backup> --yes`.

## Backup safety

Cashbook uses SQLite, so a raw `tar` of a live data directory is not treated as a trustworthy backup.

`scripts/backup.sh` therefore:

1. detects whether `cashbook-cloud` is running;
2. briefly stops the container;
3. creates a consistent archive of `deploy/data`;
4. immediately restarts the service;
5. validates the archive;
6. optionally encrypts it with AES-256-CBC + PBKDF2;
7. keeps backups for 14 days by default.

For encrypted backups, create a root-owned passphrase file outside the repository and set only its path:

```bash
mkdir -p /root/.config/cashbook
openssl rand -base64 48 > /root/.config/cashbook/backup-passphrase
chmod 600 /root/.config/cashbook/backup-passphrase
```

Then set in `deploy/.env`:

```
CASHBOOK_BACKUP_PASSPHRASE_FILE=/root/.config/cashbook/backup-passphrase
```

The passphrase itself must never be committed to GitHub.

### Restore safety

`scripts/restore.sh` validates the archive before touching live data. The old
`deploy/data` directory is renamed to `data.pre-restore-<timestamp>`, so a
failed restore can roll back automatically. After a successful restore and
manual validation, remove the rollback directory yourself.
