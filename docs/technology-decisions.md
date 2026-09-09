# Technology decisions — why each tool is here

This project intentionally uses a wide (but coherent) slice of the DevOps
toolchain. Each choice below is made for a specific, explainable reason —
useful both as documentation and as interview prep.

## Application layer

**Node.js + Express (api-gateway)**
Express is the simplest way to demonstrate a reverse-proxy / edge-service
pattern (the same role an API gateway, Nginx, or an ALB plays in a real
system) without pulling in a heavier framework. `http-proxy-middleware`
keeps the proxying logic explicit and readable rather than hidden behind
infrastructure.

**Python + FastAPI (task-service)**
FastAPI gives typed request/response models (Pydantic), automatic OpenAPI
docs, and async support with very little boilerplate — while still being
a widely-used, production-proven framework. Python is also the language
used later for Ansible-adjacent tooling and scripting, so this keeps the
stack's Python usage consistent.

**PostgreSQL**
The most common relational database in production platform work, with
first-class support in both AWS (RDS) and Kubernetes operators. Using a
real database (not SQLite) from the start makes the later observability
and troubleshooting phases (connection pooling, slow queries, backups)
meaningful.

## Containerization

**Docker (multi-stage builds)**
Multi-stage builds separate the dependency-resolution stage from the
runtime image, so the final image doesn't carry compilers, build caches,
or dev dependencies. This directly reduces attack surface and image size.

**Non-root users, healthchecks, `.dockerignore`**
These are baseline production hygiene: containers should not run as root
unless there's a specific reason to, orchestrators need a reliable signal
of container health, and build context should not leak `.git`, `.env`, or
`node_modules` into the image.

**docker-compose**
The fastest way to reproduce the full multi-service topology (gateway +
backend + database) on a laptop, with the same service names and network
boundaries the Kubernetes manifests describe.

## Orchestration

**Kubernetes (manifests, no Helm yet)**
Plain manifests in Phase 1 keep every field visible and explainable —
useful for demonstrating that the underlying resources (Deployment,
Service, ConfigMap, Secret, resource limits, probes) are understood before
introducing templating. Helm is added once there's a real templating need
(multiple environments).

**Namespace, ConfigMap, Secret (placeholder), resource requests/limits,
liveness/readiness probes**
This is the minimum manifest set that reflects how a real workload is
actually run on Kubernetes — not just "a Deployment," but one with
resource governance and health signaling a cluster operator depends on.

## CI/CD (current phase)

**GitHub Actions**
Free, tightly integrated with GitHub, and the most commonly expected CI
tool in job postings alongside Jenkins. Used here to run tests, build
images, and run security scans on every push/PR.

**hadolint**
Lints Dockerfiles for common anti-patterns (e.g. missing pinned versions,
shell-form CMD) — catches Dockerfile mistakes before they reach an image.

**Trivy**
Scans built images for known CVEs in OS packages and language
dependencies. Runs in report-only mode in Phase 1 (`exit-code: 0`); a
later phase tightens this to fail the build above a severity threshold.

A local scan during Phase 1 development found zero CRITICAL/HIGH
vulnerabilities in either service's own application dependencies. The
`task-service` image (`python:3.12-slim`) does carry unresolved
CRITICAL/HIGH findings in Debian base-image packages (e.g. `perl-base`,
`util-linux`) that have no upstream fix yet — a common, largely
unavoidable characteristic of Debian-based images, and exactly the kind
of residual risk report-only scanning is meant to surface rather than
silently ignore. Note also: the `api-gateway` image explicitly strips the
npm CLI from the runtime stage (see its Dockerfile) specifically because
it otherwise contributes a long tail of unrelated CVEs from its own
bundled dependencies — a good example of scan output driving a concrete
image-hardening decision.

**gitleaks**
Scans the git history for accidentally committed secrets (API keys,
credentials, private keys) — a real and common source of production
incidents.

## Infrastructure as Code (Phase 2)

**Terraform**
The standard IaC tool for AWS, with first-class provider support and wide
industry adoption — a more relevant skill to demonstrate than a
cloud-specific tool like CloudFormation/CDK for a portfolio meant to be
cloud-agnostic in principle. Split into three modules (`vpc`, `iam`,
`eks`) rather than one flat configuration, the same reasoning as
splitting the application into gateway/backend services: a smaller,
explicit interface per concern, reusable across environments. See
[docs/aws-architecture.md](aws-architecture.md#why-terraform-modules).

**EKS (Amazon Elastic Kubernetes Service)**
A managed control plane means no time spent operating etcd/API-server
availability — consistent with this project's principle of building real
depth in the application/platform layers it controls (manifests, CI,
IaC) rather than reinventing what a managed service already solves well.
Worker nodes run as an EKS **managed node group** (AWS handles node
provisioning/lifecycle/AMI patching triggers) rather than self-managed
EC2 Auto Scaling groups, for the same reason.

**IAM roles only — no IAM users or access keys**
Every AWS identity Terraform creates here is a role assumed by an AWS
service principal (`eks.amazonaws.com`, `ec2.amazonaws.com`), each with
only the AWS-managed policies EKS documents as the minimum required. No
long-lived access key exists anywhere in this configuration to leak.

## Configuration management (Phase 3)

**Ansible**
Configures the operating system on a standalone Linux server (packages,
timezone, an application user, Docker, Node Exporter, basic hardening) —
a job deliberately kept separate from Terraform, which only provisions
AWS infrastructure. See
[docs/ansible-architecture.md](ansible-architecture.md#why-terraform-and-ansible-not-just-one-tool)
for the full reasoning.

## GitOps delivery (Phase 4)

**Why Helm?**
Helm turns the Phase 1 hand-written manifests (`kubernetes/`) into a
templated, versioned, parameterized package: one `image.tag` value
instead of editing every Deployment by hand, one chart driven by
different `values-*.yaml` files instead of maintaining full duplicate
manifest sets per environment. It's also the de facto standard packaging
format for Kubernetes applications, and what ArgoCD integrates with
natively.

**Why ArgoCD?**
ArgoCD runs *inside* the cluster and continuously reconciles live state
against Git, rather than only pushing changes at deploy time (the model a
plain CI-driven `kubectl apply`/`helm upgrade` step would use). That
continuous reconciliation is what gives GitOps its two defining
properties: drift correction (a manual `kubectl edit` doesn't
permanently stick) and a live dashboard of "does the cluster actually
match Git right now," not just "did the last deploy succeed."

**Why GitOps?**
Making Git the source of truth means every deployed change already has
what most deployment pipelines have to build separately: a full audit
trail (who changed what, reviewed via a PR, at what commit), and a
rollback mechanism that's just a Git operation (`git revert`) rather than
a separate, only-sometimes-tested "rollback script." See
[docs/gitops-architecture.md](gitops-architecture.md) for the full
explanation, including what's actually implemented vs. only documented in
this portfolio.

**Why separate Terraform from application deployment?**
Terraform's state file tracks *infrastructure* (a VPC, an EKS cluster) —
resources with real, expensive, slow-to-recreate lifecycles. Application
deployments change far more often than infrastructure does, and shouldn't
share a state file, a plan/apply cycle, or a blast radius with a VPC route
table. Keeping them as two separate tools (and two separate Git-tracked
concerns: `terraform/` vs. `helm/`+`argocd/`) means a routine app
deployment can never accidentally touch infrastructure, and vice versa.

**Why `values-dev.yaml` and `values-prod.yaml`?**
The point of a values file per environment is that the exact same
templates/logic run in both — only the *data* differs (replica counts,
resource sizing, which Secret to reference). That's a stronger guarantee
than two independently-maintained manifest sets, which can silently drift
apart in ways that are only discovered when production behaves
differently than the environment it was supposedly tested in.

**Why avoid `latest` image tags?**
`latest` is not a version — it's a mutable pointer that can silently
change underneath a running deployment, makes "what's actually deployed
right now" unanswerable from the tag alone, and defeats rollback (there's
no previous `latest` to go back to). This chart's `image.tag` defaults to
`.Chart.AppVersion` and `values-prod.yaml`'s example uses an explicit
version string; a real registry-integrated pipeline would use the Git SHA
instead (see `.github/workflows/ci.yml`'s build-images job, which already
tags images with `${{ github.sha }}` even though nothing is pushed yet).

**Why keep secrets outside Git?**
A Git repository's history is effectively permanent and, for a public
portfolio repo, world-readable — a credential committed once (even if
later deleted) has to be treated as compromised forever. This chart's
`existingSecret` pattern (see `helm/taskflow/README.md`'s "Secrets"
section) lets real credentials live only in the cluster (created
out-of-band, e.g. via `kubectl create secret`), while everything that
*is* safe to version — the chart, the values files, which Secret name to
reference — stays in Git.

## Observability (Phase 5)

**Why Prometheus?**
The de facto standard metrics system for Kubernetes-native workloads, with
a query language (PromQL) expressive enough for everything from a simple
rate to the `histogram_quantile` calculations this project's latency
alerts use, and Kubernetes-native service discovery (`ServiceMonitor`)
that means no scrape target is ever a hardcoded IP - see
[docs/observability-architecture.md](observability-architecture.md).

**Why Grafana?**
The visualization layer every one of these tools already assumes as its
companion - Prometheus, Loki, and Alertmanager all either ship a
Grafana-compatible datasource by default or (Alertmanager) are queried by
Grafana's own alerting UI. Using anything else would mean maintaining a
second, less-integrated visualization tool for no real benefit.

**Why Loki?**
Loki indexes only a small set of **labels** (namespace, pod, container,
app - see
[observability/README.md#cardinality](../observability/README.md#cardinality)),
not full log text - dramatically cheaper to run than a full-text-indexed
system (the ELK/OpenSearch model) for a project whose actual log query
pattern is "show me this pod/namespace's logs around this time," not
free-text search across everything ever logged. It also shares Grafana as
its query UI, rather than introducing a second dashboarding tool.

**Why Alertmanager?**
Deduplication, grouping, and routing are a genuinely separate concern from
*detecting* a condition (Prometheus's job) - Alertmanager is what turns
"this expression became true" into "one grouped notification to the right
receiver, not five identical ones," and what makes inhibition (suppressing
a less-severe alert once a more-severe one for the same underlying problem
is already firing) possible at all. Bundled with Prometheus by the same
kube-prometheus-stack chart, rather than a separate integration to wire up.

**Why Kubernetes-native service discovery (ServiceMonitor)?**
A static Prometheus `scrape_configs` entry needs Prometheus's own config
reloaded every time a target changes. A `ServiceMonitor` is a Kubernetes
object the Prometheus Operator watches continuously - Prometheus's scrape
config regenerates automatically from whatever Services currently match
its label selector, the same reconciliation model ArgoCD itself uses for
GitOps. See
[observability/manifests/servicemonitor-taskflow.yaml](../observability/manifests/servicemonitor-taskflow.yaml)'s
own header comment.

**Why separate metrics and logs (Prometheus+Loki, not one system)?**
Metrics are small, structured, and cheap to keep at high cardinality-per-series
for months; logs are large, unstructured, and expensive to fully
index for anywhere near that long. Prometheus's storage engine is built
around the first workload, Loki's around the second (index labels only,
keep the actual log text cheap in object/file storage) - a single system
optimized for both would necessarily compromise on one.

**Why GitOps for observability, same as the application?**
The monitoring stack is infrastructure a real team would want the exact
same guarantees for that Phase 4 already established for the application:
a full audit trail of every alerting-threshold or dashboard change (a
reviewable Git commit, not an ad-hoc `kubectl edit` against a live
Alertmanager config), and drift correction if someone changes something
directly against the cluster. See
[argocd/README.md#observability-applications](../argocd/README.md#observability-applications)
for the multi-source Application pattern this required (an externally
hosted Helm chart, with values that still live in - and are reviewed as
part of - this Git repo).

**Why avoid public exposure by default?**
Prometheus, Alertmanager, Loki, and Grafana all default to `ClusterIP` -
none are reachable outside the cluster. Exposing Grafana or Prometheus's
own UI publicly without authentication in front of it is a common way a
monitoring stack becomes its own security incident (dashboards and raw
metrics both leak information about what's running and how it's
configured); this project reaches them via `kubectl port-forward`
instead, the same zero-extra-setup approach already used for ArgoCD's own
UI (see
[argocd/README.md#installing-argocd](../argocd/README.md#installing-argocd)).

## Networking, DNS, TLS & load balancing (Phase 6)

**Why AWS ALB (via the AWS Load Balancer Controller) instead of an
in-cluster ingress controller like NGINX?** An NGINX Ingress controller
would itself need to run behind *something* internet-facing - typically a
`LoadBalancer`-type Service, i.e. an AWS-provisioned Classic/Network Load
Balancer anyway, plus an extra layer of routing/proxying this project
would then have to operate and secure itself. The ALB approach lets AWS's
own managed load balancer be the thing the Kubernetes `Ingress` resource
configures directly - one less moving part to run, and one that
integrates natively with ACM (certificate management) and target-group
health checks without a second proxy layer translating between the two.
NGINX remains the right choice when portability across cloud providers
matters more than AWS-native integration - not the case for a project
that already commits to EKS throughout.

**Why TLS termination at the ALB, not at the Ingress/pod?** ACM issues
certificates usable only by AWS services that integrate with it directly
(ALB, CloudFront, etc.) - it never exposes the certificate's private key
for use elsewhere. Terminating anywhere else would mean sourcing and
rotating a certificate/key pair through some other mechanism entirely,
reintroducing exactly the manual certificate-management burden ACM exists
to remove. See
[docs/networking-architecture.md#tls--acm](networking-architecture.md#tls--acm).

**Why ACM specifically?** Free (for certificates used with integrated AWS
services), auto-renewing (as long as its DNS validation records remain in
place - see `terraform/modules/dns`), and requires no manual
certificate-signing-request workflow. The alternative (Let's Encrypt via
cert-manager running inside the cluster) is a legitimate choice too, but
adds an entire additional controller and its own renewal/failure surface
for a benefit (portability off AWS) this project doesn't need.

**Why Route 53?** The only DNS provider that integrates with ACM's DNS
validation and ALB alias records without any manual "copy this record
into your DNS provider's UI" step - both `terraform/modules/dns`'s
certificate validation and the optional ALB alias record are Terraform
resources precisely because Route 53 supports managing them as such.

**Why `ClusterIP` + Ingress instead of a `LoadBalancer` Service per
component?** A `LoadBalancer` Service provisions its *own* separate load
balancer per Service - three externally-reachable Services would mean
three ELBs/NLBs, three TLS certificates, three DNS records, none
coordinating with each other. One Ingress in front of one shared ALB
centralizes TLS termination and routing into a single reviewable
resource, and makes it structurally impossible to accidentally expose
`task-service`/`postgres` externally, since neither has (or needs) its
own externally-facing Service to misconfigure. See
[docs/networking-architecture.md#kubernetes-service-exposure](networking-architecture.md#kubernetes-service-exposure).

**Why IRSA for the AWS Load Balancer Controller?** The controller needs
real AWS permissions (creating/modifying ALBs, target groups, security
group rules) to do its job at all. IRSA scopes those permissions to
exactly the one Kubernetes ServiceAccount that needs them - `sts:AssumeRoleWithWebIdentity`
restricted by both `sub` (the exact `namespace:serviceaccount` pair) and
`aud` conditions - rather than either the node's own IAM role (which
every pod on that node could then implicitly use) or a long-lived IAM
user access key. This reuses the OIDC provider `terraform/modules/eks`
(Phase 2) already registers - Phase 6 adds a role, not a new trust
mechanism. See `terraform/modules/irsa/main.tf`'s own comments for the
exact trust-policy shape.

**Why NetworkPolicy, and why disabled by default?** The policies
themselves (`helm/taskflow/templates/networkpolicy.yaml`) are genuinely
correct least-privilege rules for TaskFlow's actual traffic pattern - but
a NetworkPolicy object has **no effect at all** unless the cluster's CNI
enforces it, and the default Amazon VPC CNI does not without an
explicitly-enabled configuration this Terraform doesn't set. Shipping
this enabled by default would risk implying a security guarantee that
might not actually hold on a given cluster - see
[docs/networking-architecture.md#network-policies](networking-architecture.md#network-policies)
for the full reasoning and how to verify enforcement before relying on
it.

**Why internal vs. public exposure is drawn where it is:** `api-gateway`
is the only component with any path to the internet (via the Ingress);
`task-service`, `postgres`, and the *entire* observability stack
(Prometheus/Grafana/Loki/Alertmanager, Phase 5) stay on `ClusterIP` with
no Ingress of their own, reachable only via `kubectl port-forward` for a
human, or in-cluster Service DNS for another workload. Phase 6 introducing
an external entry point for the application does not change this for
anything else - see `argocd/networking-project.yaml`'s and
`argocd/observability-project.yaml`'s separate, narrowly-scoped
AppProjects, neither of which grants the other's Application any
additional reach.

## Reserved for later phases (not yet implemented)

- **api-gateway `/metrics` endpoint** — now implemented (Phase 6, see
  `services/api-gateway/src/app.js`); this bullet is kept only as a
  pointer for anyone reading the Phase 5 summary's original "known
  limitation" note.
- **Jenkins concepts** — documented separately as a comparison to the
  GitHub Actions pipeline once CI/CD is more advanced.

See the root [README](../README.md#future-implementation-phases) for the
full phase breakdown.
