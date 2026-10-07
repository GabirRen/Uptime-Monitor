# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### M1 – Foundations

- Repository structure for `api/` (PHP 8.3, Laravel), `worker/` (Go), `app/` (TypeScript, Vite + React), and `db/`.
- `db/init.sql` with the full schema (users, auth_tokens, monitors, checks, check_rollups_hourly, incidents, alert_channels, monitor_alert_channels, notifications) and an empty `db/migrations/` for future plain-SQL changes.
- `docker-compose.yml` orchestrating `db`, `api`, `worker`, and `app` with healthchecks and `depends_on: condition: service_healthy`.
- Minimal Laravel skeleton with a single unauthenticated `GET /api/v1/health` endpoint, configured for PostgreSQL (`SESSION_DRIVER=array`, `QUEUE_CONNECTION=sync`, `CACHE_STORE=file`), with no Eloquent migrations (schema owned by `db/init.sql`).
- Minimal Go worker with structured JSON logging (`log/slog`), an internal `/healthz` endpoint for container healthchecks, and graceful shutdown on `SIGINT`/`SIGTERM`.
- Minimal Vite + React + TypeScript app skeleton (strict mode) served via `nginx-unprivileged` in production.
- Multi-stage Dockerfiles with non-root users and healthchecks for all three components.
- `.env.example` and `.gitignore` at the repository root.
- GitHub Actions CI workflow running lint and tests for `api` (Pint, PHPUnit), `worker` (`go vet`, `go build`, `go test`), and `app` (oxlint, `tsc` build, Vitest).
