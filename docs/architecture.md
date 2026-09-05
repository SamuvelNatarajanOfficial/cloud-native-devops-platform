# Architecture

## Overview

TaskFlow is a small, deliberately simple task-tracking system used as a
vehicle for demonstrating DevOps practices — not as an example of complex
application design.

```
                 ┌────────────────────┐
   Client  ───▶  │     api-gateway     │   Node.js / Express
                 │  (reverse proxy,    │   - /health, /ready
                 │   edge concerns)    │   - proxies /api/* to task-service
                 └─────────┬───────────┘
                           │ HTTP
                           ▼
                 ┌────────────────────┐
                 │    task-service     │   Python / FastAPI
                 │ (business logic,   │   - CRUD /tasks
                 │  data access)      │   - /health, /ready, /metrics
                 └─────────┬───────────┘
                           │ SQL
                           ▼
                 ┌────────────────────┐
                 │      PostgreSQL     │
                 └────────────────────┘
```

## Why split gateway and backend at all?

A single service would be simpler, but it wouldn't demonstrate anything
about service-to-service communication, independent scaling, per-service
health semantics, or the kind of topology real platform teams operate.
Two services is the minimum that makes those concerns real.

## Request flow

1. A client calls `api-gateway` (e.g. `GET /api/tasks`).
2. The gateway proxies the request to `task-service`, stripping the
   `/api` prefix.
3. `task-service` handles the request, talking to PostgreSQL via
   SQLAlchemy.
4. The response flows back through the gateway unchanged.

## Health & readiness semantics

Both services expose two endpoints, matching how Kubernetes distinguishes
liveness from readiness:

| Endpoint  | Meaning                                              | Used by            |
|-----------|-------------------------------------------------------|---------------------|
| `/health` | The process is up and able to serve requests (liveness) | Kubernetes liveness probe |
| `/ready`  | The service's dependencies are reachable (readiness)   | Kubernetes readiness probe |

- `api-gateway`'s `/ready` checks that `task-service` is reachable.
- `task-service`'s `/ready` runs `SELECT 1` against PostgreSQL.

This mirrors a real incident-response distinction: a "live but not ready"
service should be taken out of the load-balancing pool, not restarted.

## Data model

A single `tasks` table: `id` (UUID), `title`, `description`, `status`
(`todo` / `in_progress` / `done`), `created_at`, `updated_at`. Intentionally
minimal — the point of this project is the platform around the app, not
the app's domain complexity.

## Observability hooks already in place

`task-service` exposes `/metrics` in Prometheus exposition format via
`prometheus-client`. No Prometheus/Grafana/Loki/Alertmanager stack is
deployed yet — that's a later phase — but the application is already
instrumented so that stack has something real to scrape when it arrives.

## What's deliberately absent in Phase 1

- No AWS resources, no EKS cluster, no Terraform, no Ansible, no ArgoCD.
- No database migrations tool (schema is created via
  `Base.metadata.create_all` on startup) — a later phase introduces
  Alembic.
- No TLS termination, no ingress controller, no DNS.
- No persistent volume for Postgres in Kubernetes (uses `emptyDir`).

See the root [README's roadmap](../README.md#future-implementation-phases)
for when each of these arrives.
