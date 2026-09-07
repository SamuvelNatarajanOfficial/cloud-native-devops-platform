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

## Reserved for later phases (not yet implemented)

- **Prometheus / Grafana / Loki / Alertmanager** — the observability
  stack; `task-service` already exposes `/metrics` in anticipation of
  this.
- **Jenkins concepts** — documented separately as a comparison to the
  GitHub Actions pipeline once CI/CD is more advanced.

See the root [README](../README.md#future-implementation-phases) for the
full phase breakdown.
