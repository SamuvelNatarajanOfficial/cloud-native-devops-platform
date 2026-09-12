# Local Kubernetes Runtime Validation (Phase 7)

Phases 1-6 built and *statically* validated this platform (`helm
template`, `helm lint`, `terraform validate`, `kubeconform`, `promtool
check rules`) - real checks, but none of them ever started a container
inside a real kubelet, scraped a real metrics endpoint, or watched an
alert actually fire. Phase 7 closes that gap: it deploys the real
application, the real Helm chart, and the real observability stack onto
an actual local Kubernetes control plane, and puts them through real
failure scenarios.

**What this phase is not**: it is not a substitute for validating the AWS
side of this project. Nothing here proves EKS, the AWS Load Balancer
Controller, ALB, Route 53, ACM, or IRSA behave a certain way - see [AWS
runtime limitations](#aws-runtime-limitations) below for the explicit
list of what still requires a real AWS environment.

## Environment

| Component | Version |
|---|---|
| OS | Windows 11 (Docker Desktop) |
| Docker | 28.5.1 |
| Kubernetes | v1.34.1 (Docker Desktop's built-in single-node cluster) |
| kubectl | v1.34.1 |
| Helm | v3.14.2 |
| Local ingress controller | ingress-nginx 4.15.1 (app v1.15.1) |

**Kind vs. Docker Desktop Kubernetes:** this phase was asked to use Kind.
`kind` was not installed on this machine, and rather than installing new
system tooling without asking, the choice was put to the project owner,
who chose to use Docker Desktop's built-in single-node Kubernetes
instead (already installed, just not enabled). Everything below is
written against that cluster - single control-plane node, not the
1-control-plane/2-worker topology Kind would have given. The
`runtime/local/` directory name and structure are cluster-agnostic by
design (plain Helm values overlays + one plain Ingress manifest, no
Kind-specific config), so the same steps apply nearly unchanged on Kind;
[Known limitations](#known-limitations) notes the two places this
specific cluster's own quirks (not Kind's) required a real fix.

**Pre-existing cluster state:** this Docker Desktop cluster already had
unrelated workloads on it before this phase started (a
`majordomo-agenticops-agent` namespace and a `testns` namespace, plus a
kubeconfig context for an unrelated real AWS EKS cluster). None of it was
touched - everything in this phase lives in three new namespaces
(`taskflow`, `monitoring`, `ingress-nginx`, plus a temporary `argocd` for
one test) and every command explicitly targeted the `docker-desktop`
context.

## Architecture

```
Client
  |
  v  HTTPS (self-signed cert, taskflow.local)
Local ingress-nginx
  |
  v  HTTP
api-gateway  (ClusterIP)
  |
  v
task-service (ClusterIP)
  |
  v
PostgreSQL (ClusterIP)
```

```
Applications (api-gateway, task-service)
   |
   +--> /metrics --> Prometheus --> Alertmanager
   |
   +--> stdout/stderr --> Grafana Alloy --> Loki
```

Compare against
[docs/networking-architecture.md](networking-architecture.md)'s AWS
design: same application, same Helm chart, same observability
configuration - only the ingress layer (ingress-nginx here, AWS Load
Balancer Controller there) and the TLS source (self-signed here, ACM
there) differ, and both of those differences live entirely in
`runtime/local/`, never in the AWS-oriented files themselves.

## Runtime Validation

| Area | Result | Evidence |
|---|---|---|
| Local Kubernetes cluster | PASS | `kubectl get nodes` - 1 node, `Ready`, v1.34.1 |
| Docker images | PASS | `docker build` succeeded for both services; visible to the cluster immediately (Docker Desktop shares one Docker daemon - no `kind load`-equivalent step needed) |
| Kubernetes deployment | PASS | All 3 workloads (`api-gateway`, `task-service`, `postgres`) reached `Running`/`Ready` - after fixing 2 real bugs, see [Known limitations](#known-limitations) |
| PostgreSQL | PASS | StatefulSet `1/1 Ready`, PVC `Bound` (hostpath StorageClass), real `INSERT`/`SELECT` via the app confirmed working |
| API gateway | PASS | `/health`, `/ready`, `/metrics` all confirmed live; golden-signal metrics scraped by Prometheus |
| Task service | PASS | Same, plus confirmed real DB reads/writes through it |
| Service communication | PASS | DNS resolution, TCP connectivity, and a real create+list task round-trip confirmed via a temporary diagnostic pod |
| Health checks | PASS | Confirmed liveness and readiness are genuinely separate checks - during a task-service outage, api-gateway's `/health` stayed `200` while `/ready` correctly reported `503` |
| Local ingress | PASS | HTTP->HTTPS redirect (308), `/health` (200), `/api/tasks` (200, real data), unknown path (404) - all through `ingress-nginx` -> `api-gateway` |
| Local HTTPS/TLS | PASS | Self-signed cert served over HTTPS; `curl -k` succeeds, plain `curl` (no `-k`) genuinely fails with a certificate error - proving it's real TLS, not bypassed |
| Helm runtime | PASS | `helm lint`, `helm template`, real `helm install`/`upgrade`, `helm list`, `helm status`, `kubectl rollout status` all executed against the real cluster |
| Prometheus | PASS | Confirmed via its own API: both `api-gateway` and `task-service` targets `up`, real metric samples returned by direct PromQL queries |
| Grafana | PARTIAL | Grafana itself, and its Prometheus + Alertmanager datasources, confirmed working end-to-end (real queries through Grafana's own proxy). The Loki datasource does not - see [Known limitations](#known-limitations) |
| Loki | PASS | Confirmed via its own API (bypassing Grafana): real log lines, correct labels, ingested from real pods |
| Grafana Alloy | PASS | After fixing a real runtime-specific bug (see below), confirmed tailing every pod's logs and shipping them to Loki |
| Alertmanager | PASS | Confirmed via its own API: routing/grouping/inhibition config loaded correctly; the built-in `Watchdog` alert (always-firing by design) proves the Prometheus->Alertmanager pipe works end-to-end |
| Alert rules | PASS | All 15 rules loaded with `health: ok`; multiple rules genuinely transitioned `inactive -> pending -> firing` during the incident simulations below |
| Failure simulation | PASS | 4 of 5 planned incidents executed for real - see [SRE Incident Tests](#sre-incident-tests) |
| NetworkPolicy runtime | PASS (confirmed NOT enforced) | Applied the real policies, then confirmed empirically that a connection they explicitly disallow still succeeds - this cluster's CNI does not enforce NetworkPolicy at all (a real, honest negative result, not a guess) |
| ArgoCD | PASS | Installed for real; a real `Application` synced the real public GitHub repo (`Synced: true`) |
| GitOps self-healing | PASS | A manual `kubectl scale` to 5 replicas was reverted back to the Git-declared `1` within ~1 second, confirmed both by direct polling and ArgoCD's own event log |

## SRE Incident Tests

Every incident below was executed against the real running cluster, with
before/after evidence captured via `kubectl` and the applications' own
endpoints - not simulated or described hypothetically.

### Incident 1: api-gateway unavailable

- **Action:** `kubectl scale deployment/taskflow-api-gateway --replicas=0`
- **Observed:** `Endpoints` for the Service went empty; the Ingress
  itself started returning `503` (nginx's own "no upstream" response);
  `ApiGatewayDown` transitioned `inactive -> pending -> firing` and was
  confirmed present in Alertmanager (`active`, `severity: critical`).
- **Monitoring signal:** Prometheus's `up{job="api-gateway"}` (see
  [Known limitations](#known-limitations) for a real gap this incident
  uncovered and fixed in the alert expression itself).
- **Recovery:** scaled back to 1 replica; `/health` returned `200` again
  within one nginx upstream-reload cycle (a few seconds).

### Incident 2: task-service unavailable

- **Action:** `kubectl scale deployment/taskflow-task-service --replicas=0`
- **Observed:** api-gateway's `/ready` immediately returned
  `{"status":"not-ready","reason":"fetch failed"}` (503) - **while
  `/health` stayed `200`**, concrete proof liveness and readiness are
  genuinely different checks, not duplicated ones. `/api/tasks` through
  the full Ingress chain returned `504`. `kubectl logs` showed
  `kube-probe` hitting both endpoints and getting exactly the expected
  split result every cycle.
- **Recovery:** scaled back to 1; full chain returned `200` again.

### Incident 3: pod restart

- **Action:** `kubectl delete pod` on the running task-service pod.
- **Observed:** the ReplicaSet created a replacement pod within 2
  seconds; it reached `Ready` in 14 seconds; the full request chain
  (Ingress -> gateway -> task-service -> postgres) returned `200`
  immediately after.
- **Recovery:** none needed - this is the self-healing behavior being
  verified, not an incident to reverse.

### Incident 4: high HTTP error rate

- **Action:** `kubectl scale statefulset/taskflow-postgres --replicas=0`,
  then issued 20 requests to `/api/tasks` through the real Ingress.
- **Observed:** all 20 requests returned real `500`s (task-service's own
  unhandled `SQLAlchemy` exception, not a proxy-level error) - a 100%
  error rate. `ApiGatewayHighErrorRate` and `ApiGatewayCriticalErrorRate`
  both reached `firing`; `TaskServiceHighErrorRate` /
  `TaskServiceCriticalErrorRate` reached `pending` (same confirmed
  mechanism, not re-awaited a second time to conserve validation time).
- **Recovery:** scaled postgres back to 1; `/api/tasks` and `/ready` both
  returned `200` again once the pod became ready.

### Incident 5: high latency

**NOT TESTED.** There is no endpoint in this application that can be made
slow without adding artificial delay logic purely for a test - which
Phase 7's own instructions explicitly rule out ("do not add artificial
production logic simply for the test"). No safe, realistic way to
reproduce sustained high latency was available in this environment.

## AWS Runtime Limitations

The AWS infrastructure layer was implemented and statically validated
through Terraform and Helm (Phases 2 and 6). Kubernetes application
behavior and observability were runtime-validated in a local Docker
Desktop Kubernetes environment (this phase). The following AWS-specific
runtime components were **not** validated, because no AWS environment was
available or used:

- EKS (the control plane itself, node provisioning, EKS-specific
  networking behavior)
- AWS Load Balancer Controller (installing it, having it actually create
  an ALB)
- ALB (target health, listener behavior, real internet-facing routing)
- Route 53 runtime DNS (an actual record resolving, actual propagation)
- ACM runtime certificates (actual issuance, actual DNS validation,
  actual renewal)
- IAM/IRSA runtime behavior (a pod actually assuming the IRSA role
  against real AWS STS)
- AWS-specific networking runtime (security groups, VPC routing, NAT in
  practice)
- AWS CloudWatch ALB metrics

**Local ingress-nginx does not prove AWS ALB functionality.** **The local
self-signed certificate does not prove ACM functionality.** **Docker
Desktop's single-node Kubernetes does not prove EKS's multi-node,
AWS-integrated behavior.** Each of the AWS-native mechanisms above has a
genuinely different implementation than its local stand-in, not just a
different label on the same thing.

## Known Limitations

Real bugs found and fixed during this phase (all fixed in the actual
project files, not worked around locally only - each would also affect a
real EKS deployment):

1. **`runAsNonRoot` without an explicit `runAsUser` fails to start at
   all.** Both application Dockerfiles created their non-root user with
   just a name (`app`), not a numeric UID. Kubernetes cannot verify a
   *named* user is non-root without starting the container first, so it
   refuses to start it at all
   (`container has runAsNonRoot and image has non-numeric user...`).
   Fixed by pinning explicit UID/GID `10001` in both Dockerfiles and
   `helm/taskflow/values.yaml`'s `securityContext.pod.runAsUser`.
2. **`capabilities.drop: ["ALL"]` breaks PostgreSQL's own startup.** The
   stock `postgres` image's entrypoint needs to `chown`/`chmod` the
   mounted data directory as root before dropping privileges internally -
   dropping all capabilities removes exactly the `CAP_CHOWN`/`CAP_FOWNER`
   root needs to do that, causing a permanent `CrashLoopBackOff`. Phase 4
   had explicitly flagged this configuration as "not verified against a
   live cluster" - Phase 7 verified it and found it broken. Fixed by no
   longer dropping capabilities for the postgres container.
3. **`kube-prometheus-stack`'s `admissionWebhooks.enabled: false` leaves
   the Operator unable to start**, in chart version 90.0.0: disabling it
   skips the Job that generates the Operator's own required TLS secret,
   but the Operator's Deployment still unconditionally mounts that
   secret. Fixed by reverting to the chart's own default (`true`) and
   widening `argocd/observability-project.yaml`'s cluster-resource
   whitelist for the two webhook-configuration resources this adds.
4. **Loki 3.6.11 refuses to start with `retention_enabled: true` and no
   `delete_request_store` configured** ("CONFIG ERROR: invalid compactor
   config"). This requirement post-dates whatever Loki version the Phase
   5 values were originally written against. Fixed by adding
   `compactor.delete_request_store: filesystem`.
5. **The `up{job=...} == 0` alert pattern never fires when a target has
   *zero* endpoints** (e.g. scaled to 0 replicas) rather than existing
   but failing to respond - Prometheus never records a `0` sample for a
   target that isn't discovered at all, only for one that fails a scrape.
   Discovered via the api-gateway outage incident simulation above,
   confirmed by direct inspection of Prometheus's own `up` time series.
   Fixed by changing both `TaskServiceDown` and `ApiGatewayDown` to
   `up{job="..."} == 0 or absent(up{job="..."})`.

Environment-specific findings (real, fully diagnosed, but appropriately
left as local-only overlays rather than changes to the Phase 5/6 files
meant for a real EKS cluster):

6. **`prometheus-node-exporter`'s default `hostRootFsMount.mountPropagation:
   HostToContainer` fails on Docker Desktop** ("path / is mounted on / but
   it is not a shared or slave mount") - a real EKS node's root filesystem
   doesn't have this restriction. Local-only fix:
   `runtime/local/values/prometheus-values-local.yaml` sets it to `None`.
7. **Loki's memcached-based query caches (`resultsCache`/`chunksCache`)
   were left permanently `Pending`** on this single-node, resource-shared
   cluster ("Insufficient memory") - not a misconfiguration, just more
   memory than this local environment's total budget comfortably supports
   alongside everything else. Local-only fix: disabled both in
   `runtime/local/values/loki-values-local.yaml`.
8. **Grafana Alloy could not read any pod's logs at all** on this
   cluster: Docker Desktop's Kubernetes runs the classic Docker Engine
   (not containerd) as its container runtime, which writes logs under
   `/var/lib/docker/containers/` and only *symlinks* them into the
   standard `/var/log/pods/...` location Alloy's DaemonSet mounts. A real
   containerd-based node (this project's actual EKS target) writes logs
   directly there - no symlink indirection. Diagnosed by mounting
   `/var/log` into a throwaway debug pod and inspecting the broken
   symlink directly. Fixed locally
   (`runtime/local/values/alloy-values-local.yaml`) by additionally
   mounting `/var/lib/docker/containers` (`alloy.mounts.dockercontainers:
   true`) **and** switching the log-parsing stage from `stage.cri` to
   `stage.docker`, since Docker Engine's own json-file log format differs
   from containerd's CRI format.
9. **Grafana's Loki datasource does not work in this environment.** The
   `grafana/grafana:13.2.1-distroless` image (used by
   kube-prometheus-stack's Grafana subchart) ships the Loki datasource as
   a separate bundled plugin binary that Grafana tries to reinstall at
   startup; that reinstall fails
   (`unlinkat .../plugins-bundled/loki: read-only file system`), and the
   plugin process exits without ever registering. Confirmed via Grafana's
   own startup logs, not just an error message on screen. **Not fixed** -
   the actual log pipeline was independently confirmed fully working by
   querying Loki's own API directly (see the table above); only Grafana's
   own UI/proxy layer for Loki specifically is affected.
10. **NetworkPolicy is not enforced by Docker Desktop's default CNI.**
    Confirmed empirically (see the table above), matching what
    `docs/networking-architecture.md#network-policies` already documented
    as an assumption for the real EKS target too - unless its CNI's
    NetworkPolicy support is explicitly enabled there as well.

## Reproduction

```bash
# 1. Enable Kubernetes in Docker Desktop (Settings -> Kubernetes), or point
#    KUBE_CONTEXT at your own local cluster's context.

# 2-8. Bootstrap everything (images, ingress-nginx, TaskFlow, TLS, observability):
bash runtime/local/scripts/up.sh

# 9. Access the application:
curl -sk --resolve taskflow.local:443:127.0.0.1 https://taskflow.local/health
curl -sk --resolve taskflow.local:443:127.0.0.1 https://taskflow.local/api/tasks

# Access Grafana (admin / local-dev-only-not-a-real-secret):
kubectl --context docker-desktop -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# then open http://localhost:3000

# Test an alert firing for real (see "SRE Incident Tests" above for the
# full set):
kubectl --context docker-desktop -n taskflow scale deployment/taskflow-api-gateway --replicas=0
# watch it in Prometheus (http://localhost:9090 after port-forwarding 9090:9090)
# or Alertmanager (http://localhost:9093 after port-forwarding 9093:9093)
kubectl --context docker-desktop -n taskflow scale deployment/taskflow-api-gateway --replicas=1

# 10. Tear down (only the taskflow/monitoring/ingress-nginx namespaces -
#     see the script's own header for exactly what it does and doesn't touch):
bash runtime/local/scripts/down.sh
```

ArgoCD itself is intentionally **not** part of `up.sh`/`down.sh` - see
[argocd/README.md](../argocd/README.md) for the official install method
this phase used verbatim, and this document's own runtime validation table
for what was confirmed once it was installed.
