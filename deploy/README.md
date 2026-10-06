# Hetzner deployment

One Hetzner Cloud VM hosting internal apps behind a shared Traefik reverse proxy.
solidtime is the first app.

```
/opt/traefik     shared reverse proxy (ports 80/443, Let's Encrypt)
/opt/solidtime   solidtime stack (app, scheduler, queue, postgres, gotenberg)
```

## 1. Server (Hetzner Cloud Console)

1. Create server: **CX22** (or CX32), image **Ubuntu 24.04**, add your SSH key, enable **Backups**.
2. Create a **Firewall**: inbound TCP 22, 80, 443 only. Attach it to the server.
   (Docker bypasses UFW, so the Cloud Firewall is the real perimeter.)
3. DNS: `A` record `time.applitude.tech` → server IPv4 (and `AAAA` → IPv6 if you want).

## 2. Base setup (on the server, as root)

```bash
apt update && apt upgrade -y
apt install -y unattended-upgrades rsync
curl -fsSL https://get.docker.com | sh

# Shared proxy network with a fixed subnet (used for TRUSTED_PROXIES)
docker network create --subnet 172.30.0.0/24 reverse-proxy
```

Disable SSH password login (`PasswordAuthentication no` in `/etc/ssh/sshd_config`, then `systemctl restart ssh`)
after confirming key login works.

## 3. Traefik

```bash
mkdir -p /opt/traefik && cd /opt/traefik
# copy docker-compose.yml, dynamic.yml from deploy/traefik
cp .env.example .env            # set ACME_EMAIL
mkdir letsencrypt
docker compose up -d
```

## 4. solidtime

```bash
mkdir -p /opt/solidtime && cd /opt/solidtime
# copy docker-compose.yml, .env.example, laravel.env.example, backup.sh from deploy/solidtime
cp .env.example .env                 # set APP_DOMAIN, DB_PASSWORD (openssl rand -hex 32)
cp laravel.env.example laravel.env   # set APP_URL, MAIL_*, SUPER_ADMINS
mkdir -p logs app-storage && chown 1000:1000 logs app-storage

# Generate APP_KEY + Passport keys, paste output into laravel.env
docker compose run --rm scheduler php artisan self-host:generate-keys

docker compose up -d
docker compose exec app php artisan migrate --force
docker compose exec app php artisan admin:user:create "Your Name" you@applitude.tech --verify-email > /root/solidtime-admin.txt  # random password, root-only (umask 077)
docker compose exec app php artisan test:email you@applitude.tech
```

Check: `docker compose ps` (all healthy), then open `https://time.applitude.tech`.

## 5. Backups

```bash
mkdir -p /opt/backups/solidtime
crontab -e
# 30 2 * * * /opt/solidtime/backup.sh >> /var/log/solidtime-backup.log 2>&1
```

Set `STORAGE_BOX=uXXXX@uXXXX.your-storagebox.de` in `.env` for an off-server copy
(add the server's SSH key to the Storage Box first). **Test a restore once:**

```bash
docker compose exec -T database pg_restore -U solidtime -d solidtime --clean < /opt/backups/solidtime/db_<stamp>.dump
```

## Upgrading solidtime

1. Read release notes: https://github.com/solidtime-io/solidtime/releases
2. Run `./backup.sh`
3. Bump `SOLIDTIME_IMAGE_TAG` in `.env`
4. `docker compose pull && docker compose up -d && docker compose exec app php artisan migrate --force`

## Adding another internal app

Attach it to the `reverse-proxy` network and copy the Traefik labels from `solidtime/docker-compose.yml`,
changing the router/service names (`solidtime`, `solidtime-https`) and the `Host(...)` rule.
Router names must be unique across all apps.
