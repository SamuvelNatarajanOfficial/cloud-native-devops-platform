# Loki (Phase 5)

Centralized log storage for TaskFlow, queried through Grafana. See
[observability/README.md](../README.md) for the directory-wide overview
(versions, secrets, cost) and
[docs/observability-architecture.md](../../docs/observability-architecture.md)
for the full logs data-flow diagram.

## Deployment mode

`grafana/loki` supports three deployment modes. This project uses
**SingleBinary** (monolithic - one component, not split into read/write/
backend targets):

| Mode | Chart's own description | Fit for this project? |
|---|---|---|
| SingleBinary | "small installs...up to a few tens of GB/day" | **Yes** - this is exactly this project's scale. |
| SimpleScalable | "medium installs...up to about 1TB/day" | No - requires real object storage (S3/GCS/etc.), unnecessary complexity for a lab/portfolio deployment. |
| Distributed | "large installs...over 1TB/day" | No - the most operationally complex option, aimed at a scale this project will never reach. |

Storage backend is `filesystem` (the `singleBinary` pod's own 5Gi PVC) -
no S3/MinIO, since SimpleScalable/Distributed's object-storage requirement
doesn't apply to SingleBinary mode.

## Retention

`limits_config.retention_period: 168h` (7 days) - see
[observability/README.md#retention](../README.md#retention) for why this
number is a lab-appropriate default, not a production recommendation. A
real retention period depends on compliance requirements, storage cost,
and how far back troubleshooting actually needs to look.

## What's disabled, and why

- **`lokiCanary`** - continuously writes/reads a synthetic log line to
  verify the write path end-to-end. A genuinely useful production signal,
  but one more moving DaemonSet a lab environment doesn't need.
- **`test.enabled`** - this chart's `helm test` hook hard-requires the
  canary (`lokiCanary.enabled`); disabling one without the other fails
  chart rendering entirely, not just `helm test`.
- **`monitoring.selfMonitoring`** - a deprecated, Grafana-Agent-Operator-
  based self-scraping mechanism. `monitoring.serviceMonitor.enabled: true`
  (which *is* on) covers the same need - Prometheus scraping Loki's own
  `/metrics` - via the same ServiceMonitor mechanism every other component
  in this project uses.

## Single-tenant

`loki.auth_enabled: false` - this is a single-tenant deployment (one
project, one cluster). Real multi-tenant Loki (separate teams/customers
with isolated log access) would set this `true` and configure per-tenant
authentication - not a concern at this project's scale.
