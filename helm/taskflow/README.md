# taskflow (Helm chart)

## Purpose

Packages the TaskFlow application (api-gateway, task-service, PostgreSQL)
— previously hand-written as plain manifests in
[kubernetes/](../../kubernetes/) (Phase 1) — into a templated, versioned,
environment-parameterized Helm chart, for GitOps delivery via ArgoCD (see
[../../argocd/README.md](../../argocd/README.md) and
[docs/gitops-architecture.md](../../docs/gitops-architecture.md)).

This chart does not replace `kubernetes/` — that directory still works
standalone for quick local manifest testing (see its own README). This
chart is the templated equivalent, meant for Helm/ArgoCD-based delivery.

## Prerequisites

- Helm 3.x (`helm version` — this chart was validated with v3.14.2)
- A Kubernetes cluster to actually install into (optional for
  linting/templating — see [Local testing](#local-testing)): a local
  cluster (kind/minikube/Docker Desktop) or the EKS cluster from Phase 2
  (`terraform/environments/dev`)

## Chart structure

```
helm/taskflow/
├── Chart.yaml              # chart metadata (see below)
├── values.yaml              # defaults - every value documented inline
├── values-dev.yaml           # small-environment overrides
├── values-prod.yaml          # production-style example (NOT auto-deployed - see its header)
├── .helmignore
├── templates/
│   ├── _helpers.tpl          # name/label helpers shared by every template
│   ├── namespace.yaml         # optional (global.createNamespace) - off by default, see below
│   ├── configmap.yaml         # api-gateway, task-service, postgres ConfigMaps
│   ├── secret.yaml            # dev-only generated Secrets (skipped when existingSecret is set)
│   ├── api-gateway-deployment.yaml / -service.yaml
│   ├── task-service-deployment.yaml / -service.yaml
│   ├── postgres-statefulset.yaml / -service.yaml
│   ├── ingress.yaml           # Phase 6, opt-in (apiGateway.ingress.enabled) - see docs/networking-architecture.md
│   ├── networkpolicy.yaml     # Phase 6, opt-in (global.networkPolicy.enabled) - see docs/networking-architecture.md#network-policies
│   └── NOTES.txt              # printed after install/upgrade
└── README.md                  # this file
```

## Chart version vs. app version

`Chart.yaml` has two independent version fields:

- **`version`** (currently `0.1.0`): the chart's own version — bump this
  when templates, `values.yaml`'s schema, or chart metadata change,
  *whether or not the application changed*.
- **`appVersion`** (currently `0.1.0`): the TaskFlow application's own
  version, matching `services/api-gateway/package.json` and the FastAPI
  `version=` in `services/task-service/app/main.py`. Bump this when the
  application changes, *whether or not the chart's templates changed*.

They start at the same number by coincidence (both are genuinely `0.1.0`
today), not because they're tied together — a template bugfix bumps
`version` to `0.1.1` without touching `appVersion`, and a new application
release bumps `appVersion` without necessarily touching `version` at all.
`image.tag` defaults to `.Chart.AppVersion` when unset (see
[Values](#values) below) precisely because appVersion is the field that's
supposed to track the deployed application's actual version.

## Values

Every value is documented inline in `values.yaml`; the summary below
covers the ones most worth understanding.

| Value | Default | Purpose |
|---|---|---|
| `global.namespace` | `taskflow` | Namespace every resource is created in |
| `global.createNamespace` | `false` | Whether this chart creates the namespace itself — see the comment in `values.yaml` and [Namespace handling](#namespace-handling) below |
| `apiGateway.image.tag` / `taskService.image.tag` | `""` (→ `.Chart.AppVersion`) | Never defaults to `latest` — see `docs/technology-decisions.md` |
| `apiGateway.replicaCount` / `taskService.replicaCount` | `2` | Overridden to `1` in `values-dev.yaml`, `3` in `values-prod.yaml` |
| `taskService.database.existingSecret` | `""` | Name of a pre-created Secret with a `DATABASE_URL` key — see [Secrets](#secrets) |
| `postgres.auth.password` | `"changeme-dev-only"` | **Dev-only placeholder** — see [Secrets](#secrets) |
| `postgres.auth.existingSecret` | `""` | Name of a pre-created Secret with `POSTGRES_USER`/`POSTGRES_PASSWORD` keys |
| `postgres.persistence.enabled` / `.size` | `true` / `1Gi` | PVC via `volumeClaimTemplates` — see [PostgreSQL](#postgresql) |
| `apiGateway.ingress.enabled` | `false` | Phase 6 external Ingress/ALB — see [Ingress](#ingress) below |
| `global.networkPolicy.enabled` | `false` | Phase 6 least-privilege NetworkPolicies — see [Network policies](#network-policies) below |

### Ingress

Off by default (`apiGateway.ingress.enabled: false`) — turning it on
requires a real ACM certificate ARN (`apiGateway.ingress.certificateArn`)
and a domain you actually control (`apiGateway.ingress.host`), neither of
which this portfolio project has. See
[docs/networking-architecture.md#ingress](../../docs/networking-architecture.md#ingress)
for the full annotation set and reasoning, and
[terraform/modules/dns](../../terraform/modules/dns) for how a real
certificate ARN would actually be produced.

### Network policies

Off by default (`global.networkPolicy.enabled: false`) — the policies in
`templates/networkpolicy.yaml` are genuinely correct least-privilege
rules, but have **no effect at all** unless the cluster's CNI enforces
NetworkPolicy, which the default Amazon VPC CNI does not without
additional configuration this project doesn't set. See
[docs/networking-architecture.md#network-policies](../../docs/networking-architecture.md#network-policies)
before enabling this on a real cluster.

### Namespace handling

The chart does **not** create its namespace by default
(`global.createNamespace: false`). Reason: if a `Namespace` object were
one of the resources a GitOps controller manages (and potentially
prunes), deleting it from the chart — or an ArgoCD `prune` sync — would
delete *everything in that namespace*, a far bigger blast radius than
"remove one Deployment." Two safer alternatives are used instead:

- `helm install --create-namespace` for a standalone Helm install (see
  [Installation](#installation) below), or
- ArgoCD's `CreateNamespace=true` `syncOption` (see
  `argocd/application-dev.yaml`), which creates the namespace once via
  ArgoCD's own pre-sync step — not as a pruned/managed resource.

Set `global.createNamespace: true` only if you're intentionally not using
either of those.

## Installation

```bash
cd helm/taskflow

# Dev/lab install:
helm install taskflow . -f values-dev.yaml --create-namespace --namespace taskflow

# Check status:
kubectl -n taskflow get pods
```

## Upgrade

```bash
# After changing a template or values file:
helm upgrade taskflow . -f values-dev.yaml --namespace taskflow

# Preview the exact diff before upgrading (requires the helm-diff plugin:
# helm plugin install https://github.com/databus23/helm-diff):
helm diff upgrade taskflow . -f values-dev.yaml --namespace taskflow
```

## Rollback

```bash
# List revisions:
helm history taskflow --namespace taskflow

# Roll back to the previous revision:
helm rollback taskflow --namespace taskflow

# Roll back to a specific revision:
helm rollback taskflow 2 --namespace taskflow
```

This is the Helm-native rollback path (works whether or not ArgoCD is
involved) — documented here, not exercised against a real release in
this phase (no `helm install` was run against any cluster; validation
was `helm lint`/`helm template` only — see the root Phase 4 summary).
When ArgoCD manages this chart, prefer a Git revert instead — see
[argocd/README.md](../../argocd/README.md#rollback) for why, and how the
two relate.

## Linting

```bash
helm lint .
helm lint . -f values-dev.yaml
helm lint . -f values-prod.yaml
```

All three were actually run against this chart — see the root Phase 4
summary for the exact output.

## Templating

Render manifests locally without touching any cluster:

```bash
helm template taskflow . -f values-dev.yaml
helm template taskflow . -f values-prod.yaml
```

Useful variations:

```bash
# Just one template:
helm template taskflow . -f values-dev.yaml --show-only templates/api-gateway-deployment.yaml

# Validate the output is well-formed YAML/has required fields, without a
# live cluster's OpenAPI schema (kubectl needs a reachable
# apiserver even for --dry-run=client's schema validation - see
# "Local testing" below):
helm template taskflow . -f values-dev.yaml | kubectl apply --dry-run=client --validate=false -f -
```

## Local testing

No AWS/EKS access is required for `helm lint`/`helm template` — both are
fully offline. If you have a local cluster (kind, minikube, or Docker
Desktop's built-in Kubernetes), you can go further:

```bash
helm install taskflow . -f values-dev.yaml --create-namespace --namespace taskflow
kubectl -n taskflow get pods -w
kubectl -n taskflow port-forward svc/taskflow-api-gateway 8080:8080
curl http://localhost:8080/health
```

Don't assume you have one of these running — see the root Phase 4 summary
for exactly what was and wasn't tested against a live cluster in this
phase.

## Security context

`apiGateway` and `taskService` both run with:

```yaml
runAsNonRoot: true
seccompProfile: { type: RuntimeDefault }
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities: { drop: ["ALL"] }
```

This matches how the images are actually built — both Dockerfiles already
run as a dedicated non-root user (`services/api-gateway/Dockerfile`'s
`app` user, `services/task-service/Dockerfile`'s `app` user), and neither
app writes anywhere at runtime except possibly `/tmp` (an `emptyDir` is
mounted there specifically so `readOnlyRootFilesystem` doesn't break
anything that does).

`postgres` intentionally uses a **smaller** subset —
`allowPrivilegeEscalation: false` and `capabilities.drop: ["ALL"]`, but
**not** `runAsNonRoot`/`readOnlyRootFilesystem`. This is a deliberate,
documented exception, not an oversight: the official `postgres` image's
entrypoint script starts as root specifically to `chown`/prepare the data
directory on first run, then drops privileges internally via `gosu` —
forcing `runAsNonRoot: true` at the pod level would prevent that startup
sequence from ever reaching the point where it drops to the `postgres`
user, and would need either a non-root-specific image variant (e.g.
Bitnami's) or an init-container-based chown workaround to do properly.
Neither was implemented here — see
[PostgreSQL](#postgresql) below and the root Phase 4 summary's "Known
limitations."

## Resource management

Every container has both `requests` and `limits` set. The numbers in
`values.yaml`/`values-dev.yaml`/`values-prod.yaml` are portfolio/lab
defaults carried over from (and in most cases identical to)
`kubernetes/*/deployment.yaml`'s existing Phase 1 values — they are
**not** load-tested or production-tuned; treat them as a reasonable
starting point to adjust based on your own workload's actual behavior.

## Health checks

`apiGateway` and `taskService` reuse the exact `/health` and `/ready`
endpoints Phase 1 already implemented — no new endpoints were invented
for this chart:

- **readiness** (`/ready`) answers "can this pod receive traffic right
  now" — task-service checks its database connection; api-gateway checks
  it can reach task-service.
- **liveness** (`/health`) answers "is the process itself still running"
  — a plain, dependency-free check, so a slow/unreachable database
  doesn't get task-service's own process killed and restarted (which
  wouldn't fix a database problem anyway).

`postgres` reuses Phase 1's `pg_isready` exec check for both probes
(differing only in timing) — see the comment in
`templates/postgres-statefulset.yaml` for why one check is correct for
both here, unlike the HTTP services above.

## PostgreSQL

Represented as a `StatefulSet` (stable pod identity/storage) + a
`PersistentVolumeClaim` per replica (via `volumeClaimTemplates`) +
a `ClusterIP` `Service` (never publicly exposed). `postgres.replicas` is
**not** configurable — this chart runs exactly one Postgres instance, with
no streaming replication configured.

**This is not equivalent to Amazon RDS or any managed database service.**
There is no automated backup, no point-in-time recovery, no
failover/high-availability, and no automated minor-version patching here
— just a single pod with durable storage. It's appropriate for a
portfolio/lab environment demonstrating StatefulSet + PVC patterns, not
for anything that needs those guarantees.

## Secrets

Two independent secrets, each with its own `existingSecret` override:

1. **`postgres.auth`** — credentials the in-chart Postgres container
   itself uses to initialize (`POSTGRES_USER`/`POSTGRES_PASSWORD`).
   `postgres.auth.password` defaults to the obviously-fake
   `"changeme-dev-only"` (same convention as `docker-compose.yml` and
   `kubernetes/postgres/secret.example.yaml`) — **never** put a real
   password there. Set `postgres.auth.existingSecret` to a pre-created
   Secret's name instead, and the chart stops generating its own (see
   `templates/secret.yaml`).
2. **`taskService.database`** — the `DATABASE_URL` task-service actually
   reads (`services/task-service/app/database.py`). By default the chart
   assembles this from `postgres.auth.*` (pointing at the in-chart
   Postgres); set `taskService.database.existingSecret` to a pre-created
   Secret's name (with a `DATABASE_URL` key) instead — this is also how
   you'd point task-service at an external database (e.g. RDS) that
   *isn't* this chart's own Postgres at all.

`values-prod.yaml` sets both `existingSecret` fields to placeholder names
and leaves `postgres.auth.password` empty — see that file's own comments
for the exact `kubectl create secret` commands you'd run to actually
create them (not done here — they're documentation, not real secrets).

If you ever need to encrypt a value for Git instead of relying on
pre-created cluster Secrets, see `ansible/README.md`'s "Ansible Vault"
section for the same never-commit-the-password-itself principle applied
via a different tool — this chart doesn't use Vault (Helm has no
built-in equivalent); consider Sealed Secrets or External Secrets
Operator for a GitOps-native version of the same idea in a future phase.

## Services

```
Client -> api-gateway Service (ClusterIP) -> task-service Service (ClusterIP, internal only) -> postgres Service (ClusterIP, internal only)
```

`apiGateway.service.type` is configurable (defaults to `ClusterIP`; set to
`LoadBalancer` if you want a real external entry point on a cluster that
supports it). `task-service`'s and `postgres`'s Service `type` fields are
**hardcoded** `ClusterIP` in their templates (not driven by a values
field at all) — neither should ever be reachable from outside the
cluster, so there's no override that could accidentally expose them.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `helm template`/`helm install` fails with a nil pointer / missing key | Check you're using a values file from this chart (`values-dev.yaml`/`values-prod.yaml`) — a hand-written override missing a required nested key (e.g. `postgres.auth`) can cause this. |
| Pod stuck `Pending` | Usually a PVC that can't bind (no default StorageClass on your cluster — set `postgres.persistence.storageClassName` explicitly) or a resource request larger than any node can satisfy. |
| `task-service` pod `CrashLoopBackOff` | Check `DATABASE_URL` resolves — `kubectl -n taskflow logs deploy/taskflow-task-service`; confirm the postgres Service/Secret names match what `taskService.database.existingSecret` (if set) actually contains. |
| Postgres pod fails to start under a strict `securityContext` | See [Security context](#security-context) above — this is the documented postgres/non-root limitation, not a chart bug. |
| ArgoCD shows `OutOfSync` right after a healthy sync | Usually expected/transient (see `docs/gitops-architecture.md`'s "Drift detection") — check `argocd/README.md` if it persists. |

## How this fits with ArgoCD/GitOps

See [../../argocd/README.md](../../argocd/README.md) and
[docs/gitops-architecture.md](../../docs/gitops-architecture.md) for how
an already-installed ArgoCD instance uses this chart, and what "GitOps"
means in that context.
