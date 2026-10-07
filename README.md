# Uptime Monitor

Uptime Monitor is a **self-hosted** service for keeping track of the availability of websites and APIs. It checks at regular intervals that your resources respond as expected, keeps a history of uptime and latency, and alerts you by email or webhook when something stops working (and when it recovers).

It is built for freelancers, small teams, and agencies that manage multiple sites or services, for themselves or for clients, and want a simple tool that installs with a single command, doesn't depend on paid SaaS products, and keeps data under their own control.

## Key features

- HTTP/HTTPS monitoring with expected status code checks, keyword matching on the response body, and configurable timeouts
- Check intervals as low as 30 seconds, with concurrent execution of hundreds of monitors
- Automatic incident detection (open and resolve) with a consecutive-failure threshold to avoid false alarms
- Email and webhook notifications with automatic retries
- Dashboard with live status, latency charts, uptime percentages over 24h/7d/30d/90d, and incident history
- Multiple users, each with their own monitors and notification channels
- Full installation with `docker compose up`

## Quick start

```bash
git clone <repository-url> uptime-monitor
cd uptime-monitor
cp .env.example .env        # at least change POSTGRES_PASSWORD
docker compose up --build
```

Then open `http://localhost:5173`, register the first user, and add your first monitor.

## Architecture

| Component | Language | Responsibility |
|---|---|---|
| `app/` | TypeScript (Vite + React) | Dashboard, charts, monitor management |
| `api/` | PHP 8.3 (Laravel) | Authentication, CRUD, REST API exposed to the web app |
| `worker/` | Go 1.22+ | Check scheduling, concurrency, incidents, notifications |
| `db` | PostgreSQL 16 | Database shared by `api` and `worker` |

---

## Repository structure

```
uptime-monitor/
├── app/                   # TypeScript, Vite + React
├── api/                   # PHP, Laravel
├── worker/                # Go
├── db/
│   └── init.sql           # Schema, run on first start of the DB container
├── docker-compose.yml
├── .env.example
├── .github/workflows/     # CI: lint + tests for each component
├── CHANGELOG.md           # Change history by version
└── README.md
```

---

## Specifications

The following sections describe the expected behavior of the system and are the reference for development and maintenance.

## Functional requirements

### Users and authentication (PHP)
- **FR-01** Registration and login with email and password (hashed with `password_hash`, Argon2id or bcrypt).
- **FR-02** Authentication via opaque Bearer token with an expiration; only the token hash is stored in the DB. Implemented as a custom Laravel auth guard on top of the `auth_tokens` table (Sanctum's `personal_access_tokens` table is not used).
- **FR-03** Logout with token revocation.
- **FR-04** Each user can only see and modify their own resources.

### Monitor management (PHP)
- **FR-05** CRUD for monitors with the following fields: name, URL, method (`GET` or `HEAD`), interval (min 30 s), timeout, expected status code range, optional expected keyword in the body, follow redirects yes/no.
- **FR-06** Pause and resume a monitor.
- **FR-07** URL validation: only `http` and `https`; hosts resolving to private or loopback networks are rejected (SSRF protection).
- **FR-08** Limit of 50 monitors per user (configurable).

### Check execution (Go)
- **FR-09** The worker loads active monitors from the DB and runs them in parallel, each at its own interval (goroutines + tickers, or a heap-based scheduler).
- **FR-10** A check succeeds if: the request completes within the timeout, the status code is within the expected range, and, if configured, the keyword is present in the body (body read capped at 1 MB).
- **FR-11** For each check the following is stored: outcome, status code, response time, and any error message.
- **FR-12** The worker picks up monitors that are created, modified, paused, or deleted without a restart (periodic reload every 15 s).
- **FR-13** Worker pool with configurable maximum concurrency (`WORKER_MAX_CONCURRENCY`).
- **FR-14** Graceful shutdown on `SIGTERM`.
- **FR-15** The worker applies the same SSRF protection as the API, also after DNS resolution.

### Incidents and notifications (Go)
- **FR-16** A monitor goes `down` after N consecutive failures (`failure_threshold`, default 3) and returns to `up` on the first success.
- **FR-17** When a monitor goes `down` an incident is opened; when it returns to `up` the incident is closed and its duration is computed.
- **FR-18** Each time an incident is opened or closed, notifications are created for the channels linked to the monitor.
- **FR-19** Supported channels: **webhook** (JSON POST) and **email** (SMTP). Delivery with retries and exponential backoff, max 5 attempts.
- **FR-20** The worker aggregates checks into hourly statistics (`check_rollups_hourly`) and deletes raw checks older than 30 days (configurable).

### Read and statistics API (PHP)
- **FR-21** List of monitors with current status, 24h/7d/30d uptime, and average latency.
- **FR-22** Check history for a monitor with pagination and date-range filters.
- **FR-23** Time series for charts (aggregated by hour or by day).
- **FR-24** List of incidents per monitor and globally.
- **FR-25** CRUD for notification channels and linking them to monitors.

### Web app (TypeScript)
- **FR-26** Login and registration pages.
- **FR-27** Dashboard with one card per monitor (status, uptime, latest latency) and automatic refresh every 30 s.
- **FR-28** Monitor detail page with latency chart, 90-day uptime bar, and incident list.
- **FR-29** Monitor create/edit form with client-side validation.
- **FR-30** Notification channel management.
- **FR-31** Responsive interface with clear loading and error states.

---

## Non-functional requirements

- **NFR-01** `docker compose up --build` starts the whole system with no other manual steps (DB with schema, API, worker, web app).
- **NFR-02** Configuration only through environment variables, with a documented `.env.example`. No secrets in the repository.
- **NFR-03** SQL queries are always parameterized (Eloquent / query builder bindings). No concatenation of user input in raw SQL.
- **NFR-04** Healthchecks on containers (`db`, `api`, `worker`) and `depends_on` with `condition: service_healthy`.
- **NFR-05** Structured JSON logs in both the worker (`log/slog`) and the API.
- **NFR-06** Tests: PHPUnit for the API, `go test` for the worker (including tests of the threshold/incident logic), Vitest for the web app.
- **NFR-07** CI on GitHub Actions: lint and tests for all three components on every push and pull request.
- **NFR-08** JSON API responses with a uniform error format: `{"error": {"code": "...", "message": "..."}}`.
- **NFR-09** Configurable CORS, rate limiting on authentication endpoints (Laravel's built-in rate limiter).

---

## API contract (PHP)

Prefix `/api/v1`. All routes except `register` and `login` require `Authorization: Bearer <token>`.

| Method | Route | Description |
|---|---|---|
| POST | `/auth/register` | Register a user |
| POST | `/auth/login` | Returns the token |
| POST | `/auth/logout` | Revokes the current token |
| GET | `/me` | User profile |
| GET | `/monitors` | List monitors with status and summary statistics |
| POST | `/monitors` | Create a monitor |
| GET | `/monitors/{id}` | Details |
| PUT | `/monitors/{id}` | Update |
| DELETE | `/monitors/{id}` | Delete |
| POST | `/monitors/{id}/pause` | Pause |
| POST | `/monitors/{id}/resume` | Resume |
| GET | `/monitors/{id}/checks` | Check history (paginated) |
| GET | `/monitors/{id}/stats` | Time series for charts (`?range=24h\|7d\|30d\|90d`) |
| GET | `/monitors/{id}/incidents` | Incidents for the monitor |
| GET | `/incidents` | All incidents for the user |
| GET/POST | `/channels` | List / create channels |
| PUT/DELETE | `/channels/{id}` | Update / delete channel |
| PUT | `/monitors/{id}/channels` | Set the linked channels |
| GET | `/health` | Healthcheck (no auth) |

---

## Database schema (PostgreSQL)

The file `db/init.sql` must contain the following.

```sql
-- ============================================================
-- Users and authentication
-- ============================================================
CREATE TABLE users (
    id             BIGSERIAL PRIMARY KEY,
    email          VARCHAR(255) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    name           VARCHAR(100) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE auth_tokens (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash    CHAR(64) NOT NULL UNIQUE,          -- SHA-256 of the token
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,
    last_used_at  TIMESTAMPTZ
);
CREATE INDEX idx_auth_tokens_user ON auth_tokens(user_id);

-- ============================================================
-- Monitors
-- ============================================================
CREATE TABLE monitors (
    id                    BIGSERIAL PRIMARY KEY,
    user_id               BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                  VARCHAR(100) NOT NULL,
    url                   VARCHAR(2048) NOT NULL,
    method                VARCHAR(4) NOT NULL DEFAULT 'GET'
                              CHECK (method IN ('GET', 'HEAD')),
    interval_seconds      INTEGER NOT NULL DEFAULT 60
                              CHECK (interval_seconds >= 30),
    timeout_ms            INTEGER NOT NULL DEFAULT 10000
                              CHECK (timeout_ms BETWEEN 1000 AND 30000),
    expected_status_min   SMALLINT NOT NULL DEFAULT 200,
    expected_status_max   SMALLINT NOT NULL DEFAULT 299,
    expected_keyword      VARCHAR(255),
    follow_redirects      BOOLEAN NOT NULL DEFAULT TRUE,
    failure_threshold     SMALLINT NOT NULL DEFAULT 3
                              CHECK (failure_threshold BETWEEN 1 AND 10),
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,

    -- Current state, updated by the worker
    current_status        VARCHAR(10) NOT NULL DEFAULT 'unknown'
                              CHECK (current_status IN ('unknown', 'up', 'down')),
    consecutive_failures  INTEGER NOT NULL DEFAULT 0,
    last_checked_at       TIMESTAMPTZ,
    last_status_change_at TIMESTAMPTZ,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_monitors_user ON monitors(user_id);
CREATE INDEX idx_monitors_active ON monitors(is_active) WHERE is_active;

-- ============================================================
-- Checks (raw data, written by the worker)
-- ============================================================
CREATE TABLE checks (
    id               BIGSERIAL PRIMARY KEY,
    monitor_id       BIGINT NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
    checked_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    success          BOOLEAN NOT NULL,
    status_code      SMALLINT,                        -- NULL if no response
    response_time_ms INTEGER,                         -- NULL on timeout/network error
    error_message    TEXT
);
CREATE INDEX idx_checks_monitor_time ON checks(monitor_id, checked_at DESC);
CREATE INDEX idx_checks_time ON checks(checked_at);   -- for retention

-- ============================================================
-- Hourly rollups (written by the worker, read by the API for charts)
-- ============================================================
CREATE TABLE check_rollups_hourly (
    monitor_id     BIGINT NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
    hour_start     TIMESTAMPTZ NOT NULL,
    checks_total   INTEGER NOT NULL,
    checks_failed  INTEGER NOT NULL,
    avg_ms         INTEGER,
    min_ms         INTEGER,
    max_ms         INTEGER,
    p95_ms         INTEGER,
    PRIMARY KEY (monitor_id, hour_start)
);

-- ============================================================
-- Incidents (managed by the worker)
-- ============================================================
CREATE TABLE incidents (
    id           BIGSERIAL PRIMARY KEY,
    monitor_id   BIGINT NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
    started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at  TIMESTAMPTZ,
    cause        TEXT,                                 -- last observed error
    CHECK (resolved_at IS NULL OR resolved_at >= started_at)
);
CREATE INDEX idx_incidents_monitor ON incidents(monitor_id, started_at DESC);
-- At most one open incident per monitor
CREATE UNIQUE INDEX uq_incidents_open ON incidents(monitor_id) WHERE resolved_at IS NULL;

-- ============================================================
-- Notification channels and notifications
-- ============================================================
CREATE TABLE alert_channels (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        VARCHAR(10) NOT NULL CHECK (type IN ('email', 'webhook')),
    name        VARCHAR(100) NOT NULL,
    config      JSONB NOT NULL,                        -- email: {"to": "..."}; webhook: {"url": "...", "secret": "..."}
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_alert_channels_user ON alert_channels(user_id);

CREATE TABLE monitor_alert_channels (
    monitor_id  BIGINT NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
    channel_id  BIGINT NOT NULL REFERENCES alert_channels(id) ON DELETE CASCADE,
    PRIMARY KEY (monitor_id, channel_id)
);

CREATE TABLE notifications (
    id            BIGSERIAL PRIMARY KEY,
    incident_id   BIGINT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
    channel_id    BIGINT NOT NULL REFERENCES alert_channels(id) ON DELETE CASCADE,
    event         VARCHAR(10) NOT NULL CHECK (event IN ('opened', 'resolved')),
    status        VARCHAR(10) NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'sent', 'failed')),
    attempts      SMALLINT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_error    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at       TIMESTAMPTZ
);
CREATE INDEX idx_notifications_pending ON notifications(next_attempt_at) WHERE status = 'pending';
```

### Data model notes
- **Who writes what**: `api` writes to `users`, `auth_tokens`, `monitors` (configuration), `alert_channels`, and `monitor_alert_channels`. `worker` writes to `checks`, `check_rollups_hourly`, `incidents`, `notifications`, and to the state fields of `monitors` (`current_status`, `consecutive_failures`, `last_*`).
- **Notification queue in the DB**: the worker reads `pending` rows with `next_attempt_at <= now()` using `SELECT ... FOR UPDATE SKIP LOCKED`, so the system also works with multiple instances.
- **No runtime schema changes**: for every schema change, add a migration file in `db/migrations/` and update the documentation.
- **Schema ownership with Laravel**: since the schema is shared with the Go worker, `db/init.sql` and `db/migrations/` (plain SQL) are the single source of truth. Laravel does not own these tables: Eloquent models map onto them, and `php artisan migrate` is not used to create or alter them. Laravel's own drivers are configured to avoid extra tables (`SESSION_DRIVER=array`, `QUEUE_CONNECTION=sync`, `CACHE_STORE=file`).

---

## Environment variables (`.env.example`)

```
# Database
POSTGRES_DB=uptime
POSTGRES_USER=uptime
POSTGRES_PASSWORD=change_me
DB_HOST=db
DB_PORT=5432

# API (Laravel)
APP_ENV=production
APP_DEBUG=false
APP_KEY=                      # generate with: php artisan key:generate --show
DB_CONNECTION=pgsql
DB_DATABASE=${POSTGRES_DB}
DB_USERNAME=${POSTGRES_USER}
DB_PASSWORD=${POSTGRES_PASSWORD}
SESSION_DRIVER=array
QUEUE_CONNECTION=sync
CACHE_STORE=file
API_PORT=8080
TOKEN_TTL_HOURS=720
MAX_MONITORS_PER_USER=50
CORS_ALLOWED_ORIGIN=http://localhost:5173

# Worker
WORKER_MAX_CONCURRENCY=50
WORKER_RELOAD_SECONDS=15
CHECK_RETENTION_DAYS=30
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=alerts@example.com

# Web app
VITE_API_BASE_URL=http://localhost:8080/api/v1
```

---

## Development roadmap

1. **M1 – Foundations**: repo structure, `docker-compose.yml`, `db/init.sql`, healthchecks for all services, basic CI.
2. **M2 – API and auth**: registration, login, monitor CRUD, URL validation, PHPUnit tests.
3. **M3 – Worker**: scheduler, concurrent check execution, result storage, configuration reload, Go tests.
4. **M4 – Incidents and notifications**: failure threshold, incidents, notification queue, webhook and email with retries.
5. **M5 – Statistics**: hourly rollups, retention, stats and uptime endpoints.
6. **M6 – Web app**: login, dashboard, detail page with charts, monitor and channel management.
7. **M7 – Polish**: rate limiting, SSRF hardening, documentation, final README.

---

## Final acceptance criteria

- [ ] `docker compose up --build` from a clean repo brings the system up with no manual intervention.
- [ ] Registering, creating a monitor, and seeing the first checks on the dashboard takes under 2 minutes.
- [ ] Shutting down a test service being monitored opens an incident after 3 failures and sends a webhook notification; bringing it back up resolves the incident.
- [ ] With 200 active monitors the worker honors the intervals without significant scheduling lag.
- [ ] A user cannot read or modify another user's resources.
- [ ] A URL pointing to `127.0.0.1` or a private network is rejected.
- [ ] CI is green on all three components.

---

## Future developments (out of initial scope)

- TCP, ping, and SSL certificate expiry checks
- Public status page for clients
- Additional notification channels (Slack, Telegram)
- Scheduled maintenance windows
- Monitoring from multiple geographic locations
