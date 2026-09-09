# Observability (Phase 5)

Prometheus, Grafana, Loki, and Alertmanager for the TaskFlow platform -
deployed via Helm charts + ArgoCD, the same GitOps pattern Phase 4 already
established for the application itself. **Nothing in this directory has
been installed onto a real cluster** - see the Phase 5 implementation
summary's "AWS changes" and "Runtime validation" sections for exactly what
was and wasn't done, and
[docs/observability-architecture.md](../docs/observability-architecture.md)
for the full architecture (including Mermaid diagrams of the metrics and
logs data flows).

## Contents

```
observability/
├── README.md                              # this file
├── manifests/                             # plain K8s manifests (ServiceMonitor, PrometheusRule, dashboard ConfigMaps)
│   ├── servicemonitor-taskflow.yaml
│   ├── prometheusrule-taskflow.yaml
│   └── grafana-dashboards-configmaps.yaml
├── prometheus/
│   ├── values-dev.yaml                    # kube-prometheus-stack values (Prometheus + Grafana + Alertmanager + kube-state-metrics + node-exporter)
│   └── values-prod.yaml                   # documented example only - see values-prod.yaml's own header
├── grafana/
│   └── dashboards/                        # dashboard JSON - the source of truth the ConfigMaps above wrap
│       ├── taskflow-overview.json
│       ├── kubernetes-overview.json
│       └── node-overview.json
├── loki/
│   ├── README.md
│   └── values-dev.yaml
└── alloy/
    ├── README.md
    └── values-dev.yaml
```

This deviates slightly from a "one folder per tool with its own
values-dev/values-prod pair" layout: `manifests/` is split out on its own
specifically so it contains **only** valid Kubernetes manifests, never a
Helm values file - see
[servicemonitor-taskflow.yaml](manifests/servicemonitor-taskflow.yaml)'s
own header comment for why that separation matters for how ArgoCD
consumes it.

## Why kube-prometheus-stack

Prometheus, Grafana, Alertmanager, kube-state-metrics, and
prometheus-node-exporter all installed and wired together (Grafana's
Prometheus/Alertmanager datasources pre-configured, ServiceMonitors for
every bundled component already in place) by one chart, instead of five
separately-installed, separately-versioned components with their own
integration surface to get right by hand. This is *the* de facto standard
way to run this stack on Kubernetes - reproducing its ~6,000 lines of
templates/CRDs by hand would demonstrate copy-pasting, not understanding.

## Versions

| Component | Chart | Pinned version | Verified via |
|---|---|---|---|
| Prometheus / Grafana / Alertmanager / kube-state-metrics / node-exporter | `prometheus-community/kube-prometheus-stack` | `90.0.0` | GitHub Releases API, at the time this phase was written |
| Loki | `grafana/loki` | `7.3.0` | GitHub Releases API |
| Grafana Alloy | `grafana/alloy` | `1.12.1` | GitHub Releases API |

Every version above was looked up directly (GitHub's releases API for
each chart repository) rather than recalled from memory or assumed - the
same "pin deliberately, never track latest" principle
[ansible/roles/node_exporter/defaults/main.yml](../ansible/roles/node_exporter/defaults/main.yml)
already established for a systemd-installed binary. **Re-verify against
each chart repo's current releases before actually installing** -
`helm search repo prometheus-community/kube-prometheus-stack --versions` /
the equivalent for `grafana/loki` and `grafana/alloy` - since a newer
version will exist by the time anyone reads this.

## Cardinality

Every label added anywhere in this phase was chosen to have a small,
bounded set of possible values:

- **Metrics** (`services/task-service/app/main.py`'s
  `record_request_metrics` middleware): labeled by the Starlette **route
  template** (`/tasks/{task_id}`), never the resolved path - the resolved
  path would create one Prometheus time series *per task UUID ever
  requested*, a label cardinality that grows without bound for as long as
  the service runs. An unmatched route (a genuine 404 on an unknown path)
  falls back to a fixed `"unmatched"` label for the same reason.
- **Logs** ([observability/alloy/values-dev.yaml](alloy/values-dev.yaml)'s
  pipeline): labeled by `namespace`, `pod`, `container`, and `app` only -
  deliberately **not** request IDs, user IDs, full URLs, or any other
  per-event value. Loki's cost/performance model is built around a small
  number of label combinations ("streams"); a high-cardinality label
  turns every unique value into its own stream, which is the single most
  common way to make a Loki deployment slow or expensive. Anything that
  needs to be searched *within* a stream (a request ID, a specific error
  message) belongs in the **log line content** itself, queried with
  LogQL's line filters (`|= "some-request-id"`), not as a label.

## Secrets

Two secrets this phase's configuration references but does **not**
create - the same `existingSecret` pattern
[helm/taskflow/README.md#secrets](../helm/taskflow/README.md#secrets)
already established:

1. **Grafana admin credentials** - `grafana.admin.existingSecret` in
   [observability/prometheus/values-dev.yaml](prometheus/values-dev.yaml).
   Create it out-of-band before installing:
   ```bash
   kubectl create secret generic grafana-admin-credentials -n monitoring \
     --from-literal=admin-user=admin \
     --from-literal=admin-password='<a real password, not this one>'
   ```
2. **A real Alertmanager receiver's webhook/token** (Slack, PagerDuty,
   etc.) - not created at all in the dev configuration (every receiver in
   `values-dev.yaml` is a safe, no-op placeholder with no delivery channel
   configured). See
   [observability/prometheus/values-prod.yaml](prometheus/values-prod.yaml)'s
   own comment block for the exact `alertmanager.secrets` +
   `*_url_file` pattern this chart uses to inject a real webhook URL
   without ever putting it in a values file.

Nothing else in this phase needs a secret: Prometheus, Loki, and Alloy
have no credentials of their own in this configuration.

## Alerting

See [docs/observability-runbook.md#alerting-philosophy](../docs/observability-runbook.md#alerting-philosophy)
for the general principle (actionable, tied to user impact, appropriately
severe, resistant to noise), and
[observability/manifests/prometheusrule-taskflow.yaml](manifests/prometheusrule-taskflow.yaml)
for every alert rule with its own reasoning inline. Routing/grouping/
inhibition live in
[observability/prometheus/values-dev.yaml](prometheus/values-dev.yaml)'s
`alertmanager.config` block.

## Retention

| Component | Dev retention | Why |
|---|---|---|
| Prometheus | 24h, no persistent volume | Enough to demo dashboards/alerts; TSDB is lost on pod restart - an explicit lab-only tradeoff, see `values-dev.yaml`'s own comment. |
| Loki | 7 days (`limits_config.retention_period: 168h`) | Enough to demonstrate log querying across more than a single session without accumulating unbounded local disk usage on the `singleBinary` pod's 5Gi PVC. |

Neither number is a production recommendation - a real retention period
depends on compliance requirements (how long logs/metrics must be
retrievable), storage cost (this data grows without bound otherwise), and
how far back a real troubleshooting session typically needs to look. See
[observability/prometheus/values-prod.yaml](prometheus/values-prod.yaml)
for what a longer-retention, persistent configuration looks like.

## Cost

Running this stack costs real compute on top of what Phases 1-4 already
cost (see the root README's own
[Estimated cost considerations](../README.md#estimated-cost-considerations)
for the EKS/NAT/EC2 baseline): every Prometheus/Grafana/Alertmanager/Loki
pod and every per-node Alloy/node-exporter DaemonSet pod consumes the
CPU/memory requests set in each `values-dev.yaml` (kept deliberately small
- see each file's own resource blocks), and Loki's PVC plus Prometheus's
own storage (ephemeral in dev, a real PVC in the `values-prod.yaml`
example) consume disk. None of this is free, and log/metric storage in
particular grows continuously for as long as the stack runs - `terraform
destroy` (Phase 2) or scaling this stack to zero when not actively
demoing it are the practical cost levers for a portfolio project, the same
principle the root README already states for the EKS cluster itself.

## Security

- **RBAC:** kube-prometheus-stack's Operator, node-exporter DaemonSet, and
  kube-state-metrics all need cluster-wide **read** access to discover
  their scrape targets (Pods, Services, Nodes) - this is inherent to
  running a cluster-monitoring stack, not a permission this project could
  reasonably narrow to namespace-scoped Roles. See
  [argocd/observability-project.yaml](../argocd/observability-project.yaml)'s
  `clusterResourceWhitelist` for the exact (empirically verified, not
  guessed) set of cluster-scoped Kinds this actually requires - no
  cluster-admin, no wildcard.
- **Network exposure:** Prometheus, Alertmanager, Loki, and Grafana all
  use `ClusterIP` Services (each chart's own default) - **none are
  exposed publicly**. Reaching any of them (e.g. Grafana's UI) would go
  through `kubectl port-forward`, the same zero-extra-setup approach
  [argocd/README.md](../argocd/README.md#installing-argocd) already uses
  for ArgoCD itself. A future phase could add an Ingress with TLS and real
  authentication (see the root README's Phase 6) - not implemented here.
- **No public repo, no committed secret:** see [Secrets](#secrets) above.

## Known limitations

- **api-gateway has no `/metrics` endpoint.** This phase instruments
  task-service only - see
  [docs/observability-architecture.md#golden-signals](../docs/observability-architecture.md#golden-signals).
  Adding equivalent metrics to the Node/Express gateway (a `prom-client`
  dependency + middleware, mirroring task-service's approach) is a
  reasonable next increment, deliberately left out here to keep this
  phase's application change small and focused.
- **TaskFlow's ServiceMonitor/PrometheusRule live outside `helm/taskflow/`**,
  in `observability/manifests/` instead - see
  `servicemonitor-taskflow.yaml`'s own header comment. A more mature
  version of this project would move them into the application's own
  chart so the app team owns its own monitoring configuration.
- **Nothing here has been installed onto a real cluster** - see the Phase
  5 implementation summary for the full static-vs-runtime validation
  breakdown.
