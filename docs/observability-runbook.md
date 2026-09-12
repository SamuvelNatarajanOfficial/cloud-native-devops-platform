# Observability runbook (Phase 5)

Troubleshooting procedures for TaskFlow and the monitoring stack itself.
Originally written (Phase 5) the way a runbook would be written *before*
first going live - from a correct understanding of the architecture (see
[docs/observability-architecture.md](observability-architecture.md)), not
from lived experience with this specific deployment.

**Update (Phase 7):** sections [#1](#1-application-is-down),
[#2](#2-high-http-error-rate), and [#4](#4-pod-restarting) have since been
exercised for real (services scaled to zero, a real 100% error rate
generated, a pod deleted) on a local Kubernetes cluster - see
[docs/local-runtime-validation.md](local-runtime-validation.md#sre-incident-tests)
for the actual commands and observed results, which matched this
runbook's own predictions. The remaining sections are still unexercised
against a real incident.

## Alerting philosophy

Not every metric should become an alert. A good alert is:

- **Actionable** - there's a real next step someone can take, not just
  "huh, interesting."
- **Tied to user impact** - "error rate is elevated" matters because users
  are seeing failures; "an internal counter is nonzero" usually doesn't.
- **Appropriately severe** - `severity: critical` should mean "wake
  someone up," not "worth a glance next business day." Everything in
  [observability/manifests/prometheusrule-taskflow.yaml](../observability/manifests/prometheusrule-taskflow.yaml)
  is `warning` except the two conditions (`TaskServiceDown`,
  `TaskServiceCriticalErrorRate`) that genuinely mean the application is
  failing for most users right now.
- **Resistant to noise** - every alert has a `for:` duration long enough
  that a single scrape blip or a rolling deployment's brief unready window
  doesn't fire it (see that file's own header comment for the reasoning
  behind each specific duration). An alert that fires on every deploy
  trains people to ignore it.

The `inhibit_rules` in
[observability/prometheus/values-dev.yaml](../observability/prometheus/values-dev.yaml)
apply the same principle structurally: if `TaskServiceDown`-severity
(critical) is already firing for a namespace, a `warning`-severity alert
about the same `alertname`+`namespace` is suppressed rather than adding a
second, less useful notification about the same underlying problem.

## 1. Application is down

**Symptoms:** `TaskServiceDown` firing, or users report the app is
unreachable.

```bash
kubectl -n taskflow get pods
kubectl -n taskflow get deployments
kubectl -n taskflow describe pod <pod-name>
kubectl -n taskflow logs <pod-name> --previous   # if it crashed/restarted
kubectl -n taskflow get events --sort-by=.lastTimestamp
```

**Likely causes:** image pull failure, crash on startup (bad config/env
var, database unreachable - see task-service's `/ready` check in
`services/task-service/app/main.py`), resource limits too low (OOMKilled),
or the Deployment was scaled to 0.

**First checks:** is the pod `Running`? If not, what does `describe`'s
Events section say? If it's `Running` but not `Ready`, check `/ready`
directly (`kubectl -n taskflow port-forward svc/task-service 8000:8000`
then `curl localhost:8000/ready`) - a 503 there means the database
connection specifically is the problem, not the process itself.

## 2. High HTTP error rate

**Symptoms:** `TaskServiceHighErrorRate` or `TaskServiceCriticalErrorRate`
firing.

```bash
kubectl -n taskflow logs -l app.kubernetes.io/name=task-service --tail=200
kubectl -n taskflow get pods
```

In Grafana: open the
[TaskFlow Overview](../observability/grafana/dashboards/taskflow-overview.json)
dashboard's "Errors" and "Traffic" panels, broken down `by (path)`, to see
which route is actually failing - a single endpoint erroring looks very
different from every request failing.

**Likely causes:** a recent deployment introduced a bug, the database is
unreachable or rejecting connections (check Postgres:
`kubectl -n taskflow get pods -l app.kubernetes.io/name=postgres`), or a
downstream dependency changed behavior.

**First checks:** correlate the alert's start time against
`kubectl -n taskflow rollout history deployment/task-service` - if it
lines up with a recent rollout, `kubectl -n taskflow rollout undo
deployment/task-service` is the fastest mitigation (see
[argocd/README.md#rollback](../argocd/README.md#rollback) for the
GitOps-native equivalent: reverting the Git commit instead).

## 3. High latency

**Symptoms:** `TaskServiceHighLatency` firing.

In Grafana: the "Latency" panel's p50 vs. p95 `by (path)` breakdown - a
high p95 with a normal p50 usually means a subset of requests (e.g. one
slow endpoint, or contention) rather than uniform slowness.

```bash
kubectl top pods -n taskflow          # CPU/memory pressure on the pod itself
kubectl -n taskflow get pods -l app.kubernetes.io/name=postgres
```

**Likely causes:** database query slowness (missing index, lock
contention, connection pool exhaustion), CPU throttling (check the pod's
resource limits vs. actual usage), or a genuinely higher load than usual
(check the "Traffic" panel for a concurrent spike in request rate).

## 4. Pod restarting

**Symptoms:** `TaskFlowPodRestartingFrequently` firing.

```bash
kubectl -n taskflow get pods
kubectl -n taskflow describe pod <pod-name>   # look at "Last State" and "Reason"
kubectl -n taskflow logs <pod-name> --previous
```

**Likely causes:** `OOMKilled` (check `describe`'s "Last State" -
resource limits too low, or an actual memory leak), a failing liveness
probe (the process is up but `/health` isn't responding in time - check
`livenessProbe` timing in
[helm/taskflow/values.yaml](../helm/taskflow/values.yaml)), or the process
itself crashing on an unhandled exception (check the logs from before the
restart).

## 5. Pod not ready

**Symptoms:** `TaskFlowPodNotReady` or `TaskFlowDeploymentReplicaMismatch`
firing.

```bash
kubectl -n taskflow get pods -o wide
kubectl -n taskflow describe pod <pod-name>   # look at the Readiness probe's own failure reason
kubectl -n taskflow get endpoints            # is the pod actually in the Service's endpoint list?
```

**Likely causes:** for task-service specifically, `/ready` fails when its
database connection isn't usable (see
`services/task-service/app/main.py`) - check Postgres health first. For
api-gateway, `/ready` fails when it can't reach task-service - a
`TaskFlowPodNotReady` on api-gateway with task-service itself healthy
usually points at a NetworkPolicy, DNS, or Service selector mismatch
rather than either application's own code.

## 6. Node resource pressure

**Symptoms:** `NodeHighCPUUsage`, `NodeHighMemoryUsage`, or
`NodeFilesystemSpacePressure` firing.

```bash
kubectl top nodes
kubectl describe node <node-name>            # "Allocated resources" section
kubectl get pods -A -o wide --field-selector spec.nodeName=<node-name>
```

**Likely causes:** too many pods scheduled on too few nodes (check the EKS
managed node group's `desired_node_count` -
`terraform/environments/dev/terraform.tfvars.example`), a single pod
consuming far more than its resource requests suggested it would, or (for
filesystem pressure specifically) accumulated container image layers/logs
- `kubectl describe node` surfaces active eviction pressure directly if
it's already occurred.

## 7. Prometheus target down

**Symptoms:** `PrometheusTargetDown` firing.

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get servicemonitor
kubectl -n taskflow get endpoints task-service   # does the Service actually have endpoints?
```

In Grafana/Prometheus's own UI: Status -> Targets shows every scrape
target and its last error, if any - the fastest way to see *why* a
specific target is down (connection refused, DNS failure, TLS error)
rather than just that it is.

**Likely causes:** the target pod itself is down (see [#1](#1-application-is-down)),
a `ServiceMonitor`/label mismatch (compare
`observability/manifests/servicemonitor-taskflow.yaml`'s `selector`
against the actual Service's labels: `kubectl -n taskflow get svc
task-service --show-labels`), or a NetworkPolicy blocking Prometheus's
pod-to-pod traffic into the target namespace.

## 8. Logs missing in Loki

**Symptoms:** no results for `{namespace="taskflow"}` in Grafana's Explore
view or the TaskFlow Overview dashboard's logs panel.

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=alloy
kubectl -n monitoring logs -l app.kubernetes.io/name=alloy --tail=100
kubectl -n monitoring get pods -l app.kubernetes.io/name=loki
```

**Likely causes:** Alloy isn't running on the node the pod is scheduled
on (check the DaemonSet has a pod per node: `kubectl -n monitoring get
pods -o wide -l app.kubernetes.io/name=alloy`), the hostPath log mount
isn't finding files (verify `mounts.varlog: true` actually took effect -
see `observability/alloy/values-dev.yaml`), or Loki itself is unreachable
from Alloy (check `loki.write` errors in Alloy's own logs - the endpoint
URL depends on the Loki Helm release being named exactly `loki`, see
`argocd/application-dev-observability-loki.yaml`'s `helm.releaseName`).

## 9. Grafana datasource unavailable

**Symptoms:** a Grafana panel shows "Bad Gateway" / "datasource not
found" instead of data.

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana
kubectl -n monitoring get svc
```

**Likely causes:** the target service (Prometheus, Alertmanager, or Loki's
`loki-gateway`) isn't running or its Service name doesn't match what's
configured in
[observability/prometheus/values-dev.yaml](../observability/prometheus/values-dev.yaml)'s
`grafana.additionalDataSources` - this is exactly why Helm release names
are pinned explicitly in every observability Application (see
`argocd/application-dev-observability-*.yaml`) rather than left to
ArgoCD's default naming.

## 10. Alert not firing

**Symptoms:** a condition you'd expect to page (e.g. the app is visibly
erroring) isn't showing up as an alert.

In Prometheus's own UI: Alerts page shows every rule's current state
(`Inactive`/`Pending`/`Firing`) - `Pending` means the condition is true but
hasn't been true for the full `for:` duration yet, which is by design (see
[Alerting philosophy](#alerting-philosophy) above), not a bug.

```bash
kubectl -n monitoring get prometheusrule
kubectl -n monitoring get pods -l app.kubernetes.io/name=alertmanager
```

**Likely causes:** the `PrometheusRule` object wasn't picked up (check
`ruleSelectorNilUsesHelmValues: false` is actually set - see
`observability/prometheus/values-dev.yaml` - without it, a
`PrometheusRule` from outside kube-prometheus-stack's own Helm release is
silently ignored), the underlying expression's metric doesn't exist for
this specific target for some other reason (re-run the alert's own `expr`
directly in Prometheus's query UI), or the alert is `Firing` in Prometheus
but Alertmanager itself is down/unreachable (check its pods directly).
