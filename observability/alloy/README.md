# Grafana Alloy (Phase 5)

The log collector: tails every pod's container logs on each node and
ships them to Loki. See [observability/README.md](../README.md) for the
directory-wide overview and
[docs/observability-architecture.md](../../docs/observability-architecture.md)
for the full logs data-flow diagram.

## Why Alloy, not Promtail

Promtail is the log collector most existing Loki tutorials still show, and
was the default pairing for years. Grafana Labs has since put Promtail
into maintenance-only mode, with **Grafana Alloy as its official,
actively-developed replacement** - building a new deployment on Promtail
today means building on a component Grafana itself is moving users away
from. Alloy is also a single, general-purpose telemetry collector (logs,
metrics, traces) rather than a Loki-specific tool, which is the direction
the broader observability tooling ecosystem (OpenTelemetry Collector and
similar) has moved as well.

## How the pipeline works

`controller.type: daemonset` (this chart's own default - not overridden
here, but worth stating explicitly since it's *why* the pipeline below
works at all): one Alloy pod per node, each mounting that node's own
`/var/log` (`alloy.mounts.varlog: true`) - the same directory kubelet
writes every pod's container logs into
(`/var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log`).

The pipeline itself (`alloy.configMap.content` in
[values-dev.yaml](values-dev.yaml), written in Alloy's River configuration
language and validated with `alloy validate` - see the Phase 5
implementation summary):

1. `discovery.kubernetes` - discovers every Pod in the cluster via the
   Kubernetes API.
2. `discovery.relabel` - keeps only pods scheduled on **this** node (via
   `sys.env("ALLOY_NODE_NAME")`, injected through the Downward API - see
   `alloy.extraEnv` in the values file), and attaches `namespace`, `pod`,
   `container`, and `app` labels (see
   [observability/README.md#cardinality](../README.md#cardinality) for
   why nothing higher-cardinality is added here).
3. `local.file_match` + `loki.source.file` - tails the actual log files at
   the path the previous step computed.
4. `loki.process` with `stage.cri` - unwraps the container runtime's log
   line wrapper (containerd's CRI format) so Loki stores the
   application's own log line with its own real timestamp.
5. `loki.write` - pushes to Loki's `loki-gateway` Service (see
   `argocd/application-dev-observability-loki.yaml`'s pinned
   `helm.releaseName: loki`, which is what makes this DNS name
   predictable).

## Why `dockercontainers` mount is left off

`alloy.mounts.dockercontainers` mounts the legacy Docker runtime's raw
JSON log path (`/var/lib/docker/containers`). EKS (and current Kubernetes
generally) uses **containerd**, which writes only under `/var/log/pods` -
the `dockercontainers` mount would be dead configuration for this
project's actual target environment.
