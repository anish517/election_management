# 🗳️ EMS — Enterprise Election Management System

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Django](https://img.shields.io/badge/Django-5.1-092E20?logo=django&logoColor=white)](https://www.djangoproject.com)
[![SQLite](https://img.shields.io/badge/SQLite-3-003B57?logo=sqlite&logoColor=white)](https://www.sqlite.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Optional-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![Celery](https://img.shields.io/badge/Celery-5.4-37814A?logo=celery&logoColor=white)](https://docs.celeryq.dev)
[![Redis](https://img.shields.io/badge/Redis-7.x-DC382D?logo=redis&logoColor=white)](https://redis.io)
[![License](https://img.shields.io/badge/License-Proprietary-blue.svg)](#)

An enterprise-grade, secure, multi-tenant digital and physical election management platform designed for professional associations, political parties, universities, cooperative societies, and statutory elections. 

EMS delivers complete end-to-end election governance: from organizational voter roll curation and nomination vetting to multi-channel secret ballot casting (Mobile App, Web Magic Link, Physical In-Person Kiosk) and cryptographically auditable mathematical results calculation (FPTP, Nepal Samānupātik PR Modified Sainte-Laguë, Parallel Mixed, IRV, and Referendums).

---

## 📑 Table of Contents

- [Architectural Overview](#-architectural-overview)
- [Key Platform Features](#-key-platform-features)
  - [1. Multi-Delivery Election Methods](#1-multi-delivery-election-methods)
  - [2. Comprehensive Voting Systems & Math Engines](#2-comprehensive-voting-systems--math-engines)
  - [3. Strict Anonymity & Cryptographic Audit Trail](#3-strict-anonymity--cryptographic-audit-trail)
  - [4. Paid Nominations & Static QR Ledger](#4-paid-nominations--static-qr-ledger)
  - [5. Election Lifecycle & Automated State Machine](#5-election-lifecycle--automated-state-machine)
- [Technology Stack](#-technology-stack)
- [Directory Structure](#-directory-structure)
- [Prerequisites & System Requirements](#-prerequisites--system-requirements)
- [Local Development Setup](#-local-development-setup)
  - [Backend Setup (Django & Celery)](#backend-setup-django--celery)
  - [Frontend Setup (Flutter Web & Mobile)](#frontend-setup-flutter-web--mobile)
- [Testing & Quality Assurance](#-testing--quality-assurance)
- [Production Deployment Guide](#-production-deployment-guide)
- [Security & Compliance Checklist](#-security--compliance-checklist)

---

## 🏛️ Architectural Overview

```mermaid
graph TD
    subgraph Clients["Client Access Layers"]
        MOB["📱 Mobile App (Android / iOS)"]
        WEB["💻 Web Portal (Desktop / Mobile Browser)"]
        KIOSK["🖥️ In-Person Venue Kiosk Booth"]
        AUDIT_CLI["🔍 Independent Auditor Verification Portal"]
    end

    subgraph Gateway["Edge & Gateway"]
        NGINX["Nginx Reverse Proxy & SSL (HTTPS/WSS)"]
    end

    subgraph Backend["Django 5 Core Backend (REST API)"]
        AUTH["Auth & Multi-Tenancy RBAC"]
        ELEC["Election State Machine & Timers"]
        CAND["Nominations, Slates & Quotas"]
        VOTE["Decoupled Anonymized Voting Engine"]
        TALLY["Mathematical Tally Service (Sainte-Laguë / FPTP)"]
        AUDIT["Cryptographic Audit & Merkle Chain"]
        NOTIF["Notification Gateway (Sparrow SMS / SMTP)"]
        BILLING["Payment Verification Ledger (Khalti / eSewa / Bank)"]
    end

    subgraph Storage["Datastores & Queues"]
        DB[("Database: SQLite 3 (Default) / PostgreSQL")]
        REDIS[("Redis 7 (Broker & Cache)")]
        CELERY["Celery Worker & Celery Beat Scheduler"]
        MEDIA["Media Storage (Stamps, Logos, Slips)"]
    end

    MOB --> NGINX
    WEB --> NGINX
    KIOSK --> NGINX
    AUDIT_CLI --> NGINX

    NGINX --> AUTH
    AUTH --> DB
    ELEC --> DB
    CAND --> DB
    VOTE --> DB
    TALLY --> DB
    AUDIT --> DB
    BILLING --> DB

    ELEC --> CELERY
    NOTIF --> CELERY
    CELERY --> REDIS
    AUTH --> REDIS
```

---

## 🌟 Key Platform Features

### 1. Multi-Delivery Election Methods
EMS natively supports four distinct delivery channels defined under two statutory methods:

* **Method 1: Online / Remote Voting**
  * **Type 1 — Mobile App Only (`mobile_app`)**: Voting is strictly restricted to authenticated native Android/iOS mobile devices. Web-based ballot requests are blocked with statutory advisories.
  * **Type 2 — Web-Based Magic Link (`web_based`)**: Single-use, cryptographically salted 24-hour direct ballot tokens dispatched via verified email or SMS OTP. Automatically burned upon cast (replay attempts return `410 Gone`).
  * **Type 3 — Hybrid (`hybrid`)**: Dual-access flexibility allowing voters to cast their ballot either via the mobile application or through a secure web magic link.
* **Method 2: Physical Venue / Device-Based In-Person Kiosks (`venue`)**
  * **Polling Station Initialization**: Election officers lock tablets or laptops into a secure full-screen booth using a Station Security PIN.
  * **Standby Check-In**: Voters unlock their ballot using their unique Voter ID and printed PIN slip (with optional 2nd-layer SMS/email OTP).
  * **5-Second Auto-Reset Loop**: Upon ballot submission, the station displays a green cryptographic confirmation and animated countdown ring (`5... 4... 3... 2... 1... 0`), automatically purging active memory and returning to standby for the next voter in line.
  * **Zero Double-Voting**: Instant database-level flag locking prevents any voter from checking in more than once.

---

### 2. Comprehensive Voting Systems & Math Engines

* **First-Past-The-Post (FPTP)**: Plurality candidate counting with automatic multi-seat allocation, tie-breaking protocols, and statutory uncontested (*Nirbirod* / निर्विरोध) declarations.
* **Nepal Proportional Representation (Samānupātik / समानुपातिक)**:
  * Official closed party list representation based on statutory election law.
  * **Modified Sainte-Laguë Quota Engine**: Mathematical divisors ($1.4, 3, 5, 7, 9, \dots$) allocating seats sequentially across qualified parties.
  * **Electoral Threshold Filter**: Automatic disqualification of parties failing to meet the legal threshold (e.g., 3.00%), with full round-by-round quotient transparency.
  * **Automated Candidate Selection**: Priority assignment according to candidates' registered `pr_rank` and inclusion quotas.
* **Mixed / Parallel Election System**:
  * Unified dual ballot paper presenting both Direct Constituency candidates (FPTP) and National Party Lists (Samānupātik) simultaneously.
  * Dual tally engine producing candidate winners and proportional seat distributions in parallel.
* **Ranked-Choice Voting (IRV)**: Instant-runoff multi-round preference redistribution.
* **Approval & Weighted Voting**: Multi-choice selection with proportional shareholder/member voting weights.
* **Referendums (Yes/No)**: Statutory issue plebiscites with configurable super-majority thresholds (e.g. 66.7%).

---

### 3. Strict Anonymity & Cryptographic Audit Trail

* **Decoupled Ballot Architecture**: In strict compliance with secret ballot standards, the `votes` table possesses **no foreign key, session token, or voter identity reference** linking to `voter_rolls`.
* **SHA-256 Cryptographic Receipts**: Each ballot cast produces a cryptographic receipt hash generated from:
  $$\text{Receipt Hash} = \text{SHA-256}(\text{Ballot JSON} \parallel \text{Cryptographic Salt} \parallel \text{Session Token})$$
* **Independent Auditor Portal**:
  * Receipt Lookup endpoint (`/v1/elections/<id>/audit/receipt/<hash>/`) allowing voters and observers to verify that a receipt exists in the sealed ballot box without disclosing ballot content.
  * Ballot Box Consistency verification (`/v1/elections/<id>/audit/verify-hash/`) calculating live Merkle root hashes across all stored ballots.
  * Export Package (`/v1/elections/<id>/audit/export/`) producing a sealed, timestamped JSON verification bundle for statutory election records.

---

### 4. Paid Nominations & Static QR Ledger

* **Configurable Nomination Charges**: Organizations set specific application fees per contestable position.
* **Static QR Financial Ledger**: Direct integration with Nepal digital payment rails:
  * **eSewa** QR & Wallet transfer
  * **Khalti** QR & Wallet transfer
  * **Bank Account / IPS Direct Transfer**
* **Voucher / Slip Verification Flow**:
  * Candidates submit transaction reference numbers and payment voucher screenshots.
  * Organization Admins review proof in the Payment Ledger, with options to **Approve**, **Reject**, or **Request Correction**.

---

### 5. Election Lifecycle & Automated State Machine

EMS enforces an immutable, forward-only statutory state machine:

```
[Draft] ➡️ [Notice Published] ➡️ [Nomination Open] ➡️ [Nomination Closed]
   ⬇️
[Verification Underway] ➡️ [Candidate List Published] ➡️ [Objection Period]
   ⬇️
[Final Candidates Published] ➡️ [Voting Open] ➡️ [Voting Closed]
   ⬇️
[Results Provisional] ➡️ [Results Final]
```

* **Automated Celery Timers**: Celery Beat continually audits scheduled milestones and advances election states precisely when date/time boundaries are crossed.

---

## 🛠️ Technology Stack

| Layer | Technology | Purpose |
| :--- | :--- | :--- |
| **Backend Framework** | Django 5.1.4 / Python 3.11+ | Enterprise web framework and security core |
| **API Architecture** | Django REST Framework (DRF) | RESTful API endpoints, serializers & permissions |
| **Database** | SQLite 3 (Default, Zero-Setup) / PostgreSQL (Optional) | Embedded ACID storage via `ems_dev.db` or external PostgreSQL |
| **Cache & Task Broker**| Redis 7.x | High-throughput in-memory cache & Celery queue broker |
| **Background Tasks** | Celery 5.4.0 + Celery Beat | Asynchronous email/SMS dispatch & state scheduler |
| **Security & Auth** | SimpleJWT + Argon2 + SHA-256 | JWT authentication, password hashing, receipt hashing |
| **Frontend Web/Mobile**| Flutter 3.x / Dart 3.12+ | Unified responsive codebase for Web, Android, iOS, Kiosk |
| **State Management** | Riverpod 2.6+ | Reactive, compile-safe dependency injection & state |
| **Web Routing** | GoRouter 14.6+ | Declarative routing with URL parameter synchronization |
| **Charts & Analytics** | FL Chart 1.2+ | Interactive voter turnout telemetry & results graphs |
| **Local Calendar** | Nepali Date Picker & Utils | Bikram Sambat (B.S.) date selection & formatting |

---

## 📁 Directory Structure

```
f:\election_management\
├── backend\                           # Django REST API Backend
│   ├── apps\                          # Domain-driven modular applications
│   │   ├── audit\                     # Cryptographic receipts & audit exports
│   │   ├── billing\                   # Nomination fees & payment voucher ledger
│   │   ├── candidates\                # Nominations, closed lists & quotas
│   │   ├── core\                      # Base models, middleware & permissions
│   │   ├── elections\                 # State machine, methods & positions
│   │   ├── members\                   # Member roster & CSV import/export
│   │   ├── notifications\             # Sparrow SMS & SMTP email templates
│   │   ├── organizations\             # Multi-tenant entities & branding
│   │   ├── results\                   # Mathematical tally & Sainte-Laguë engine
│   │   ├── users\                     # Custom User model & RBAC
│   │   └── voting\                    # Ballot builder, sessions & kiosk service
│   ├── ems_backend\                   # Project settings, Celery app & root URLs
│   ├── manage.py                      # Django management script
│   ├── requirements.txt               # Python package dependencies
│   └── test_all_methods_and_systems_e2e.py # 25/25 automated E2E test suite
│
├── election_management\               # Flutter Multi-Platform Client
│   ├── android\                       # Android native project & manifest
│   ├── assets\                        # Images, election symbols & animations
│   ├── lib\
│   │   ├── core\                      # Network clients, API constants & theme
│   │   ├── features\                  # Feature modules
│   │   │   ├── admin\                 # Admin election management & candidate review
│   │   │   ├── auth\                  # Login, OTP verification & registration
│   │   │   ├── dashboard\             # Executive statistics & telemetry
│   │   │   ├── elections\             # Election lists & candidate profiles
│   │   │   ├── results\               # Real-time results, charts & CSV export
│   │   │   ├── venue_kiosk\           # Full-screen booth check-in & 5s auto-reset
│   │   │   └── voting\                # Touch-friendly ballot screen & confirmation
│   │   └── main.dart                  # Application entry point & router setup
│   └── pubspec.yaml                   # Flutter dependencies & assets config
│
├── DEPLOYMENT_GUIDE.md                # Complete production deployment manual
├── ELECTION_METHODS_MANUAL_TESTING_GUIDE.md # Step-by-step human testing guide
├── start_all.ps1                      # Windows development one-click launcher
└── vercel.json                        # Vercel static web deployment configuration
```

---

## 💻 Prerequisites & System Requirements

### Hardware Requirements
* **Development**: 4 Core CPU, 8 GB RAM, 10 GB Disk space.
* **Production**: 4+ vCPU, 16 GB RAM, 50 GB NVMe SSD storage (scales with voter concurrency).

### Software Requirements
* **Python**: `v3.11` or `v3.12`
* **Flutter SDK**: `v3.24+` (Stable channel)
* **Database**: SQLite 3 (built-in with Python, zero setup) or PostgreSQL 15/16 (optional)
* **Redis Server**: `v7.0+`
* **Node.js** (optional, for web tooling): `v20 LTS`

---

## 🚀 Local Development Setup

### Backend Setup (Django & Celery)

1. **Clone the repository**:
   ```bash
   git clone https://github.com/anish517/election_management.git
   cd election_management
   ```

2. **Set up Python Virtual Environment**:
   ```bash
   # Windows (PowerShell)
   python -m venv venv
   .\venv\Scripts\Activate.ps1

   # Linux / macOS
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Install Dependencies**:
   ```bash
   pip install -r backend_requirements.txt
   ```

4. **Configure Environment Variables**:
   Copy `.env.example` in `backend/` to `.env`:
   ```bash
   cd backend
   cp .env.example .env
   ```
   Configure your database credentials in `backend/.env`:
   ```ini
   DEBUG=True
   SECRET_KEY=django-insecure-dev-secret-key-change-in-production
   
   # Default Database: SQLite (Embedded in ems_dev.db, zero setup needed)
   DATABASE_URL=sqlite:///./ems_dev.db
   
   # Optional: PostgreSQL (For high-concurrency production deployments)
   # DATABASE_URL=postgres://ems_user:ems_password@localhost:5432/ems_db
   REDIS_URL=redis://localhost:6379/0
   FRONTEND_URL=http://localhost:3000
   ALLOWED_HOSTS=localhost,127.0.0.1,192.168.110.108
   CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
   ```

5. **Run Database Migrations**:
   ```bash
   python manage.py migrate
   ```

6. **Create Default Super Admin**:
   ```bash
   python manage.py createsuperuser
   ```

7. **Start Celery Services** (in separate terminal windows):
   * **Terminal 1 — Celery Worker**:
     ```bash
     celery -A ems_backend worker --pool=solo -l info
     ```
   * **Terminal 2 — Celery Beat (Scheduler)**:
     ```bash
     celery -A ems_backend beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler
     ```
   * **Terminal 3 — Django Server**:
     ```bash
     python manage.py runserver 0.0.0.0:8000
     ```

> 💡 **Windows Tip**: You can launch Redis, Celery Worker, and Celery Beat in one click by running `powershell -ExecutionPolicy Bypass -File .\start_all.ps1`.

---

### Frontend Setup (Flutter Web & Mobile)

1. **Navigate to the Flutter App Directory**:
   ```bash
   cd f:\election_management\election_management
   ```

2. **Get Packages**:
   ```bash
   flutter pub get
   ```

3. **Run on Web** (Chrome):
   ```bash
   flutter run -d chrome --web-port=3000
   ```

4. **Run on Physical Android Device or Emulator**:
   ```bash
   # List connected devices
   flutter devices

   # Run on target device
   flutter run -d <DEVICE_ID>
   ```

---

## 🧪 Testing & Quality Assurance

### Automated End-to-End Test Suite
EMS features an automated verification suite in `backend/test_all_methods_and_systems_e2e.py` testing **25 critical compliance checks**:

* **Suite 1**: Method 1 Type 2 Web-Based OTP, magic link issuance, direct cast & token burn.
* **Suite 2**: Method 1 Type 1 Mobile App Only restriction and authorized mobile casting.
* **Suite 3**: Method 2 Venue Kiosk PIN unlock, secret ballot cast, instant receipt & double-voting block.
* **Suite 4**: Samānupātik PR 3% threshold check, disqualification of fringe parties, and Sainte-Laguë seat distribution.
* **Suite 5**: Parallel Mixed System dual FPTP candidate winner + PR party list allocation.
* **Suite 6**: 100-Ballot cryptographic receipt chain integrity, audit receipt lookup, and JSON export.

Run the test suite:
```bash
cd backend
python test_all_methods_and_systems_e2e.py
```
**Expected Result**:
```
===========================================================================
  E2E VERIFICATION COMPLETE: 25/25 CHECKS PASSED
  VERDICT: ALL METHODS, VOTING SYSTEMS, BALLOTS & RESULTS PASS WITH 100% ACCURACY! 🎉
===========================================================================
```

### Static Analysis
Verify Flutter frontend code quality:
```bash
cd election_management
flutter analyze
```
*(Clean output: `No issues found!`)*

---

## 📖 Production Deployment Guide

For complete, step-by-step production instructions including:
* **Docker & Docker Compose** production stack setup
* **Ubuntu 22.04/24.04 LTS Bare-Metal** systemd services (Gunicorn + Celery + Redis)
* **Nginx Reverse Proxy & SSL (Let's Encrypt)** configuration
* **Flutter Web Production Build** & static CDN deployment
* **Android Release APK & Google Play App Bundle (AAB)** signing
* **PostgreSQL Performance Tuning & Automated Daily Backups**

👉 **Please refer to the comprehensive [DEPLOYMENT_GUIDE.md](file:///f:/election_management/DEPLOYMENT_GUIDE.md)**.

---

## 🔒 Security & Compliance Checklist

- [x] **Zero-Knowledge Ballot Decoupling**: Identity strictly separated from ballot choices.
- [x] **Replay Protection**: Single-use tokens burned atomically using database-level transaction locks.
- [x] **Anti-Tamper Audit Logging**: Every state change, nomination action, and verification attempt logged with IP address and user agent.
- [x] **Station Auto-Reset**: In-person venue kiosks automatically wipe memory and return to standby within 5 seconds of ballot casting.
- [x] **Cross-Site Protection**: CORS, CSRF, and HTTP Strict Transport Security (HSTS) headers enforced.

---

## 📄 License & Intellectual Property

Copyright © 2026 EMS Platform. All rights reserved. Proprietary software developed for certified statutory and organizational elections.
