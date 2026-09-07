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

## Reserved for later phases (not yet implemented)

- **Ansible** — configuration management for anything not natively
  Kubernetes-managed.
- **ArgoCD** — GitOps-based continuous delivery once there's a
  Git-defined desired state to reconcile against the EKS cluster.
- **Prometheus / Grafana / Loki / Alertmanager** — the observability
  stack; `task-service` already exposes `/metrics` in anticipation of
  this.
- **Jenkins concepts** — documented separately as a comparison to the
  GitHub Actions pipeline once CI/CD is more advanced.

See the root [README](../README.md#future-implementation-phases) for the
full phase breakdown.
