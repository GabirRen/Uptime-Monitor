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
