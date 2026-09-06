# 🚀 EMS Enterprise Production Deployment Guide

> **Note on Deployment Architecture**:  
> While platforms like Vercel were utilized during initial UI prototyping and transient client-side preview testing, **enterprise elections demand sovereign, self-hosted, tamper-evident infrastructure**. Statutory secret balloting, high-concurrency voter turnout, mathematical PR tally computation, and cryptographic audit chains require dedicated Linux or containerized Cloud hosting.

This guide provides exhaustive, battle-tested instructions for deploying the **Election Management System (EMS)** to production using either **Docker Compose** (recommended for rapid containerized orchestration) or **Native Ubuntu 22.04/24.04 LTS** (recommended for bare-metal / dedicated cloud instances).

---

## 📑 Table of Contents

1. [System Architecture & Capacity Planning](#1-system-architecture--capacity-planning)
2. [Domain & SSL Blueprint](#2-domain--ssl-blueprint)
3. [Production Environment Variables Reference](#3-production-environment-variables-reference)
4. [Deployment Approach A: Docker Compose Stack](#4-deployment-approach-a-docker-compose-stack-recommended)
5. [Deployment Approach B: Ubuntu 22.04/24.04 LTS Bare-Metal](#5-deployment-approach-b-ubuntu-22042404-lts-bare-metal)
   - [5.1 Operating System & Package Setup](#51-operating-system--package-setup)
   - [5.2 PostgreSQL 16 Production Setup](#52-postgresql-16-production-setup)
   - [5.3 Redis Server Setup](#53-redis-server-setup)
   - [5.4 Django Core Application Setup](#54-django-core-application-setup)
   - [5.5 Systemd Services (Gunicorn, Celery Worker, Celery Beat)](#55-systemd-services-gunicorn-celery-worker-celery-beat)
   - [5.6 Nginx Reverse Proxy & Let's Encrypt SSL](#56-nginx-reverse-proxy--lets-encrypt-ssl)
6. [Flutter Production Builds](#6-flutter-production-builds)
   - [6.1 Flutter Web Production Compilation & Deployment](#61-flutter-web-production-compilation--deployment)
   - [6.2 Android APK & Google Play App Bundle (AAB)](#62-android-apk--google-play-app-bundle-aab)
   - [6.3 Venue Kiosk Hardware Lockdown](#63-venue-kiosk-hardware-lockdown)
7. [Database Backup & Disaster Recovery](#7-database-backup--disaster-recovery)
8. [Production Security Hardening Checklist](#8-production-security-hardening-checklist)

---

## 1. System Architecture & Capacity Planning

A production EMS deployment comprises five core services:
1. **Nginx Web Server / Reverse Proxy**: Edge SSL termination, static asset cache, rate limiting, and reverse proxying to Gunicorn and Flutter Web.
2. **Gunicorn WSGI Application Server**: Multi-worker Python WSGI server handling Django REST API requests.
3. **Celery Worker**: Asynchronous queue worker processing SMS OTPs (Sparrow SMS), emails, PDF receipts, and audit bundle packaging.
4. **Celery Beat**: Periodic state machine advancement engine (evaluates election milestones every 60 seconds).
5. **Database (SQLite 3 / PostgreSQL 16)**: Embedded ACID storage via `ems_dev.db` (default out-of-the-box, zero external setup) or PostgreSQL 16 (for high-concurrency multi-voter elections).
6. **Redis 7 In-Memory Datastore**: Fast task broker and session cache.

```mermaid
graph TD
    CLIENT["🌐 Voters & Admins (Web / Mobile / Kiosk)"]
    DNS["Cloudflare DNS / Route 53 (SSL / DDoS Shield)"]
    NGINX["Nginx (Ports 80 & 443 — Reverse Proxy & SSL)"]
    
    subgraph AppServer["EMS Application Host"]
        WEB_STATIC["/var/www/ems/web (Flutter Web Static Bundle)"]
        MEDIA_STATIC["/var/www/ems/media (Uploaded Logos, Stamps, Slips)"]
        GUNICORN["Gunicorn (127.0.0.1:8000 — 4-8 WSGI Workers)"]
        CEL_WORKER["Celery Worker (Task Queue Execution)"]
        CEL_BEAT["Celery Beat (State Advancement Cron)"]
    end

    subgraph DataServer["Datastores"]
        DB[("Database: SQLite 3 (Default) / PostgreSQL")]
        REDIS[("Redis 7 (Broker & Cache)")]
    end

    CLIENT --> DNS
    DNS --> NGINX
    NGINX -- "GET /" --> WEB_STATIC
    NGINX -- "GET /media/*" --> MEDIA_STATIC
    NGINX -- "API: /v1/*, Admin: /admin/*" --> GUNICORN
    
    GUNICORN --> DB
    GUNICORN --> REDIS
    CEL_WORKER --> REDIS
    CEL_WORKER --> DB
    CEL_BEAT --> REDIS
    CEL_BEAT --> DB
```

### Hardware Sizing Matrix

| Expected Concurrent Voters | Total Eligible Voters | Recommended Specs | Gunicorn Workers | Database Pool |
| :--- | :--- | :--- | :--- | :--- |
| **Small (1 - 50 req/s)** | Up to 10,000 | 2 vCPU, 4 GB RAM, 40 GB SSD | 3 workers | 20 connections |
| **Medium (50 - 250 req/s)**| Up to 100,000 | 4 vCPU, 8 GB RAM, 80 GB SSD | 5 workers | 50 connections |
| **Large (250 - 1,000 req/s)**| 100,000 - 1,000,000 | 8 vCPU, 16 GB RAM, 160 GB NVMe | 9 workers | 100 connections |
| **National Scale (1,000+ req/s)**| 1,000,000+ | Dedicated Cluster + DB Read Replicas | 16+ workers | External RDS/Aurora |

---

## 2. Domain & SSL Blueprint

We recommend configuring a unified single domain or split subdomains:

* **Unified Strategy (Recommended)**:
  * `https://voting.yourdomain.com/` ➡️ Serves Flutter Web App
  * `https://voting.yourdomain.com/v1/` ➡️ Proxies to Django REST Backend
  * `https://voting.yourdomain.com/admin/` ➡️ Proxies to Django Admin
  * `https://voting.yourdomain.com/media/` ➡️ Nginx direct media file serving
* **Split Subdomain Strategy**:
  * `https://vote.yourdomain.com/` ➡️ Frontend
  * `https://api-vote.yourdomain.com/` ➡️ Backend

---

## 3. Production Environment Variables Reference

Create a secured `.env` file (`chmod 600 .env`) in your backend directory:

```ini
# =============================================================================
# EMS Production Environment Configuration
# Location: /var/www/ems/backend/.env
# =============================================================================

# Django Security Core
DEBUG=False
SECRET_KEY=generate-a-64-character-random-secret-key-do-not-share
ALLOWED_HOSTS=voting.yourdomain.com,api.yourdomain.com,127.0.0.1,localhost

# SSL & Security Headers (Mandatory in Production)
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
SECURE_HSTS_SECONDS=31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
SECURE_HSTS_PRELOAD=True
SECURE_PROXY_SSL_HEADER=HTTP_X_FORWARDED_PROTO,https

# CORS & CSRF Trusted Origins
CORS_ALLOWED_ORIGINS=https://voting.yourdomain.com
CSRF_TRUSTED_ORIGINS=https://voting.yourdomain.com

# Database Configuration
# Option 1: SQLite (Default out-of-the-box, zero external database setup required)
DATABASE_URL=sqlite:///./ems_dev.db

# Option 2: PostgreSQL (Recommended for high-concurrency production elections)
# Format: postgres://<user>:<password>@<host>:<port>/<dbname>
# DATABASE_URL=postgres://ems_user:StrongPasswordHere123!@127.0.0.1:5432/ems_prod

# Redis Cache & Task Queue
REDIS_URL=redis://127.0.0.1:6379/0

# JWT Authentication
JWT_ACCESS_TOKEN_LIFETIME_MINUTES=30
JWT_REFRESH_TOKEN_LIFETIME_DAYS=7

# Sparrow SMS Gateway (Nepal Production)
SPARROW_SMS_TOKEN=your_sparrow_sms_token_here
SPARROW_SMS_FROM=SparrowSMS

# SMTP Email Gateway (SendGrid / Amazon SES / Dedicated Mail Server)
EMAIL_HOST=smtp.sendgrid.net
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=apikey
EMAIL_HOST_PASSWORD=your_sendgrid_production_api_key
DEFAULT_FROM_EMAIL=EMS Official <noreply@yourdomain.com>

# Frontend URL (Used in automated email direct ballot magic links)
FRONTEND_URL=https://voting.yourdomain.com

# Super Admin Initialization (Created automatically during initial migration)
SUPER_ADMIN_EMAIL=election.commission@yourdomain.com
SUPER_ADMIN_PHONE=+9779800000000
SUPER_ADMIN_PASSWORD=InitialAdminPasswordMustChange!
```

---

## 4. Deployment Approach A: Docker Compose Stack (Recommended)

Docker Compose encapsulates all services with isolated dependencies, automatic health restarts, and automated volume persistence.

### Step 1: Clone Repository & Prepare Directory
```bash
sudo mkdir -p /opt/ems
sudo chown -R $USER:$USER /opt/ems
git clone https://github.com/anish517/election_management.git /opt/ems
cd /opt/ems
```

### Step 2: Configure Production Environment
```bash
cp backend/.env.example /opt/ems/.env.production
nano /opt/ems/.env.production
# Fill in your production passwords, domain names, and SMS/Email API keys.
```

### Step 3: Launch Containers
Run the production compose stack:
```bash
docker compose -f docker-compose.prod.yml up -d --build
```

### Step 4: Run Initial Database Migrations & Superuser
```bash
docker compose -f docker-compose.prod.yml exec backend python manage.py migrate
docker compose -f docker-compose.prod.yml exec backend python manage.py collectstatic --noinput
docker compose -f docker-compose.prod.yml exec backend python manage.py createsuperuser
```

### Step 5: Verify Container Health
```bash
docker compose -f docker-compose.prod.yml ps
```
All containers (`ems_nginx`, `ems_backend`, `ems_celery_worker`, `ems_celery_beat`, `ems_postgres`, `ems_redis`) should display state `healthy` or `running (Up)`.

---

## 5. Deployment Approach B: Ubuntu 22.04/24.04 LTS Bare-Metal

For maximum raw performance on dedicated VPS (DigitalOcean Droplet, AWS EC2, Hetzner, Linode, or On-Premise Server).

### 5.1 Operating System & Package Setup

1. **Update and upgrade system packages**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y curl git ufw build-essential libpq-dev python3-dev python3-pip python3-venv \
                       postgresql postgresql-contrib redis-server nginx certbot python3-certbot-nginx \
                       libjpeg-dev zlib1g-dev libffi-dev libcairo2 libpango-1.0-0 libpangocairo-1.0-0
   ```

2. **Configure UFW Firewall**:
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow OpenSSH
   sudo ufw allow 'Nginx Full'
   sudo ufw enable
   ```

3. **Create Dedicated System User**:
   ```bash
   sudo adduser --system --group --no-create-home ems
   ```

---

### 5.2 PostgreSQL 16 Production Setup

1. **Start and enable PostgreSQL**:
   ```bash
   sudo systemctl enable postgresql
   sudo systemctl start postgresql
   ```

2. **Create Production Database & User**:
   ```bash
   sudo -u postgres psql
   ```
   Execute the following SQL statements:
   ```sql
   CREATE DATABASE ems_prod;
   CREATE USER ems_user WITH PASSWORD 'StrongPasswordHere123!';
   ALTER ROLE ems_user SET client_encoding TO 'utf8';
   ALTER ROLE ems_user SET default_transaction_isolation TO 'read committed';
   ALTER ROLE ems_user SET timezone TO 'Asia/Kathmandu';
   GRANT ALL PRIVILEGES ON DATABASE ems_prod TO ems_user;
   ALTER DATABASE ems_prod OWNER TO ems_user;
   \q
   ```

3. **PostgreSQL Performance Tuning**:
   Edit `/etc/postgresql/16/main/postgresql.conf` (adjust paths based on your PG version):
   ```ini
   max_connections = 100
   shared_buffers = 2GB          # 25% of total RAM
   effective_cache_size = 6GB    # 75% of total RAM
   maintenance_work_mem = 512MB
   checkpoint_completion_target = 0.9
   wal_buffers = 16MB
   default_statistics_target = 100
   random_page_cost = 1.1        # SSD setting
   work_mem = 20MB
   ```
   Restart PostgreSQL:
   ```bash
   sudo systemctl restart postgresql
   ```

---

### 5.3 Redis Server Setup

1. **Enable and configure Redis**:
   Edit `/etc/redis/redis.conf`:
   ```ini
   supervised systemd
   maxmemory 512mb
   maxmemory-policy allkeys-lru
   ```
2. **Restart Redis**:
   ```bash
   sudo systemctl restart redis-server
   sudo systemctl enable redis-server
   redis-cli ping  # Should output: PONG
   ```

---

### 5.4 Django Core Application Setup

1. **Create Web Root and Clone Application**:
   ```bash
   sudo mkdir -p /var/www/ems
   sudo chown -R $USER:$USER /var/www/ems
   git clone https://github.com/anish517/election_management.git /var/www/ems/source
   mv /var/www/ems/source/backend /var/www/ems/backend
   ```

2. **Set Up Python Virtual Environment**:
   ```bash
   cd /var/www/ems/backend
   python3 -m venv venv
   source venv/bin/activate
   pip install --upgrade pip setuptools wheel
   pip install -r requirements.txt
   pip install gunicorn uvicorn
   ```

3. **Configure Environment Variables**:
   ```bash
   cp .env.example .env
   nano .env  # Insert production DATABASE_URL, SECRET_KEY, REDIS_URL, etc.
   chmod 600 .env
   ```

4. **Run Migrations & Collect Static Files**:
   ```bash
   python manage.py migrate
   python manage.py collectstatic --noinput
   ```

5. **Create Media and Static Directories with Proper Permissions**:
   ```bash
   sudo mkdir -p /var/www/ems/backend/media /var/www/ems/backend/staticfiles
   sudo chown -R ems:ems /var/www/ems/backend/media
   sudo chmod -R 775 /var/www/ems/backend/media
   ```

---

### 5.5 Systemd Services (Gunicorn, Celery Worker, Celery Beat)

#### 1. Gunicorn Application Service
Create `/etc/systemd/system/ems-backend.service`:
```ini
[Unit]
Description=Gunicorn daemon for EMS Django Backend
After=network.target postgresql.service redis-server.service

[Service]
User=ems
Group=ems
WorkingDirectory=/var/www/ems/backend
EnvironmentFile=/var/www/ems/backend/.env
ExecStart=/var/www/ems/backend/venv/bin/gunicorn \
          --access-logfile /var/log/ems_gunicorn_access.log \
          --error-logfile /var/log/ems_gunicorn_error.log \
          --workers 5 \
          --worker-class uvicorn.workers.UvicornWorker \
          --bind 127.0.0.1:8000 \
          --timeout 120 \
          --graceful-timeout 30 \
          ems_backend.asgi:application
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### 2. Celery Worker Service
Create `/etc/systemd/system/ems-celery-worker.service`:
```ini
[Unit]
Description=Celery Worker for EMS Background Tasks (Email/SMS/Receipts)
After=network.target redis-server.service postgresql.service

[Service]
Type=forking
User=ems
Group=ems
WorkingDirectory=/var/www/ems/backend
EnvironmentFile=/var/www/ems/backend/.env
ExecStart=/var/www/ems/backend/venv/bin/celery multi start worker1 \
          -A ems_backend --pidfile=/var/run/celery/worker1.pid \
          --logfile=/var/log/celery/worker1.log --loglevel=INFO --concurrency=4
ExecStop=/var/www/ems/backend/venv/bin/celery multi stopwait worker1 \
         --pidfile=/var/run/celery/worker1.pid
ExecReload=/var/www/ems/backend/venv/bin/celery multi restart worker1 \
           -A ems_backend --pidfile=/var/run/celery/worker1.pid \
           --logfile=/var/log/celery/worker1.log --loglevel=INFO
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### 3. Celery Beat Scheduler Service
Create `/etc/systemd/system/ems-celery-beat.service`:
```ini
[Unit]
Description=Celery Beat Periodic Scheduler for EMS Election State Advancement
After=network.target ems-celery-worker.service

[Service]
User=ems
Group=ems
WorkingDirectory=/var/www/ems/backend
EnvironmentFile=/var/www/ems/backend/.env
ExecStart=/var/www/ems/backend/venv/bin/celery -A ems_backend beat \
          --loglevel=INFO \
          --scheduler django_celery_beat.schedulers:DatabaseScheduler \
          --pidfile=/var/run/celery/beat.pid \
          --logfile=/var/log/celery/beat.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### Create Log and PID directories & Enable Services:
```bash
sudo mkdir -p /var/log/celery /var/run/celery
sudo chown -R ems:ems /var/log/celery /var/run/celery
sudo touch /var/log/ems_gunicorn_access.log /var/log/ems_gunicorn_error.log
sudo chown ems:ems /var/log/ems_gunicorn*.log

sudo systemctl daemon-reload
sudo systemctl enable --now ems-backend
sudo systemctl enable --now ems-celery-worker
sudo systemctl enable --now ems-celery-beat
```

Check status:
```bash
sudo systemctl status ems-backend ems-celery-worker ems-celery-beat
```

---

### 5.6 Nginx Reverse Proxy & Let's Encrypt SSL

1. Create Nginx site configuration at `/etc/nginx/sites-available/ems.conf`:
```nginx
# Rate Limiting Zones (DDoS protection for OTP and ballot endpoints)
limit_req_zone $binary_remote_addr zone=vote_limit:10m rate=15r/s;
limit_req_zone $binary_remote_addr zone=api_general:10m rate=50r/s;

server {
    listen 80;
    server_name voting.yourdomain.com;

    # Redirect all HTTP traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name voting.yourdomain.com;

    # SSL Certificates (managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/voting.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/voting.yourdomain.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Maximum file upload size (for voter lists and candidate nomination PDFs)
    client_max_body_size 25M;

    # 1. Django Backend API & Admin endpoints
    location ~ ^/(v1|admin)/ {
        limit_req zone=api_general burst=20 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        proxy_read_timeout 120s;
        proxy_connect_timeout 60s;
    }

    # Strict rate limit for direct vote casting & OTP verification
    location ~ ^/v1/voting/(direct-cast|kiosk/cast|verify-web-otp)/ {
        limit_req zone=vote_limit burst=10 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # 2. Django Static Files
    location /static/ {
        alias /var/www/ems/backend/staticfiles/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # 3. Uploaded Candidate Photos, Official Stamps & Payment Slips
    location /media/ {
        alias /var/www/ems/backend/media/;
        expires 7d;
        add_header Cache-Control "public, no-transform";
    }

    # 4. Flutter Web Production App (Single Page Application fallback)
    root /var/www/ems/web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Caching rules for Flutter web artifacts
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

2. **Enable Site & Obtain SSL Certificate**:
   ```bash
   sudo ln -s /etc/nginx/sites-available/ems.conf /etc/nginx/sites-enabled/
   sudo rm -f /etc/nginx/sites-enabled/default
   sudo certbot --nginx -d voting.yourdomain.com
   sudo nginx -t && sudo systemctl reload nginx
   ```

---

## 6. Flutter Production Builds

### 6.1 Flutter Web Production Compilation & Deployment

Compile Flutter Web on your development workstation or CI/CD runner:

1. **Navigate to the Flutter directory**:
   ```bash
   cd f:\election_management\election_management
   ```

2. **Clean and fetch dependencies**:
   ```bash
   flutter clean
   flutter pub get
   ```

3. **Build Release Web Bundle with Production API URL**:
   ```bash
   flutter build web --release --dart-define=API_BASE_URL=https://voting.yourdomain.com/v1
   ```

4. **Deploy Compiled Assets to Server**:
   Copy the contents of `build/web/` to the production server at `/var/www/ems/web/`:
   ```bash
   # From local machine:
   scp -r build/web/* user@your-server-ip:/var/www/ems/web/
   ```

5. **Ensure Correct Ownership**:
   ```bash
   # On server:
   sudo chown -R www-data:www-data /var/www/ems/web
   sudo chmod -R 755 /var/www/ems/web
   ```

---

### 6.2 Android APK & Google Play App Bundle (AAB)

#### Step 1: Generate Release Keystore
Run keytool from your terminal:
```bash
keytool -genkey -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ems-release
```
Place `release-keystore.jks` in `election_management/android/app/`.

#### Step 2: Configure `key.properties`
Create `election_management/android/key.properties` (never commit this file to git):
```properties
storePassword=YourKeystorePasswordHere
keyPassword=YourKeyPasswordHere
keyAlias=ems-release
storeFile=release-keystore.jks
```

#### Step 3: Build Signed Release Artifacts
```bash
cd f:\election_management\election_management

# 1. Build Standalone Release APK (for direct distribution or mobile testing):
flutter build apk --release --dart-define=API_BASE_URL=https://voting.yourdomain.com/v1

# Output location:
# build/app/outputs/flutter-apk/app-release.apk

# 2. Build Google Play Store Bundle (AAB):
flutter build appbundle --release --dart-define=API_BASE_URL=https://voting.yourdomain.com/v1

# Output location:
# build/app/outputs/bundle/release/app-release.aab
```

---

### 6.3 Venue Kiosk Hardware Lockdown

For in-person polling stations using physical tablets or laptops:

1. **Tablets (Android / iPad)**:
   * Use **Fully Kiosk Browser** or Android Native Screen Pinning.
   * Lock URL to: `https://voting.yourdomain.com/#/elections/<election-id>/kiosk`.
   * Disable navigation bar, status pull-down, and home buttons.
2. **Laptops (Ubuntu / Windows)**:
   * Run Google Chrome in dedicated kiosk mode:
     ```bash
     chrome.exe --kiosk "https://voting.yourdomain.com/#/elections/<election-id>/kiosk" --disable-pinch --overscroll-history-navigation=0
     ```
3. **Printer Pairing**: Connect Bluetooth or ESC/POS USB thermal printers for instant Voter PIN Slip issuance.

---

## 7. Database Backup & Disaster Recovery

Implement automated, off-site database backups to prevent data loss during statutory elections.

### Automated Backup Script
Create `/usr/local/bin/ems-backup.sh`:
```bash
#!/bin/bash
set -e

BACKUP_DIR="/var/backups/ems_postgres"
DATE=$(date +'%Y-%m-%d_%H-%M-%S')
FILENAME="ems_prod_$DATE.sql.gz"

mkdir -p "$BACKUP_DIR"

# Dump database compressed
PGPASSWORD="StrongPasswordHere123!" pg_dump -U ems_user -h 127.0.0.1 ems_prod | gzip > "$BACKUP_DIR/$FILENAME"

# Retain only last 14 days of backups locally
find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +14 -delete

# (Optional) Sync to AWS S3 or Backblaze B2
# aws s3 cp "$BACKUP_DIR/$FILENAME" s3://your-secure-election-backups/
```

Make executable and configure cron:
```bash
sudo chmod +x /usr/local/bin/ems-backup.sh
sudo crontab -e
```
Add line to backup every 6 hours during voting period:
```cron
0 */6 * * * /usr/local/bin/ems-backup.sh > /var/log/ems_backup.log 2>&1
```

### Database Restore Procedure
```bash
# In case of emergency disaster recovery:
gunzip -c /var/backups/ems_postgres/ems_prod_2026-09-06.sql.gz | psql -U ems_user -h 127.0.0.1 ems_prod
```

---

## 8. Production Security Hardening Checklist

| Item | Control | Verification |
| :--- | :--- | :--- |
| **Debug Mode** | `DEBUG=False` in Django settings | Request non-existent route; returns generic 404, not traceback |
| **Secret Key** | 64+ char random string | Stored exclusively in `.env`, not hardcoded in repo |
| **HTTPS Only** | HTTP redirects to HTTPS + HSTS | SSL Labs gives A+ rating on `voting.yourdomain.com` |
| **Firewall** | UFW active; only ports 22, 80, 443 open | `sudo ufw status` confirms ports 5432 and 6379 are blocked |
| **Secret Ballot Isolation** | No foreign keys between `votes` and `voter_rolls` | Verify database schema integrity |
| **Rate Limiting** | Nginx `limit_req` on vote cast endpoints | Rapid bursts return HTTP 429 Too Many Requests |
| **Single-Use Burn** | Web tokens burned atomically | Second vote attempt returns HTTP 410 Gone |
| **Audit Logs** | All state changes and admin actions persisted | Check `/v1/elections/<id>/audit/logs/` |

---

## 📞 Support & Incident Escalation

For production election operations, technical assistance, or critical security advisories:
* **System Operations Team**: `devops@emsplatform.com`
* **Security & Statutory Auditing**: `security@emsplatform.com`
