# cloud-native-devops-platform

A production-inspired, cloud-native microservices platform built as a
public portfolio project to demonstrate hands-on DevOps / platform
engineering skills — from containerization through (eventually)
infrastructure-as-code, GitOps, and observability on AWS/EKS.

> This is a personal portfolio project, built incrementally in phases.
> See [Future implementation phases](#future-implementation-phases) for
> what exists today versus what's planned.

## Project overview

**TaskFlow** is a small task-tracking application: an API gateway in
front of a backend service backed by PostgreSQL. The application itself
is intentionally simple — its purpose is to give real DevOps tooling
(CI/CD, containers, Kubernetes, and later IaC/GitOps/observability)
something concrete to build, test, deploy, and monitor.

## Project objectives

- Demonstrate a realistic, multi-service application deployed with
  production-minded practices (non-root containers, health probes,
  resource limits, layered CI checks).
- Build up, phase by phase, a complete cloud-native delivery pipeline:
  containers → Kubernetes → Terraform/AWS/EKS → Ansible →
  Helm/ArgoCD (GitOps) → observability
  (Prometheus/Grafana/Loki/Alertmanager).
- Keep every phase independently reviewable, so the git history itself
  tells the story of how the platform was built.

## Architecture overview

```
Client → api-gateway (Node/Express) → task-service (Python/FastAPI) → PostgreSQL
```

See [docs/architecture.md](docs/architecture.md) for the full breakdown,
including health/readiness semantics and data model.

## Technology stack

| Layer            | Technology                                   |
|-------------------|-----------------------------------------------|
| Edge / gateway     | Node.js, Express                               |
| Backend service    | Python, FastAPI, SQLAlchemy                    |
| Database           | PostgreSQL                                     |
| Containers         | Docker (multi-stage builds)                    |
| Local orchestration| docker-compose                                 |
| Container orchestration | Kubernetes (plain manifests)             |
| Infrastructure as Code | Terraform (AWS VPC, IAM, EKS)             |
| Target cloud       | AWS (EKS)                                      |
| Configuration management | Ansible (Linux server config, Docker, Node Exporter, hardening) |
| Packaging          | Helm (templated, environment-parameterized chart) |
| GitOps delivery     | ArgoCD (not yet installed - see Phase 4 below)   |
| Observability       | Prometheus, Grafana, Loki, Alertmanager, Grafana Alloy (not yet installed - see Phase 5 below) |
| CI/CD              | GitHub Actions                                 |
| Security scanning  | hadolint, Trivy, gitleaks                      |

See [docs/technology-decisions.md](docs/technology-decisions.md) for the
reasoning behind each choice.

## DevOps practices demonstrated

- Multi-stage Docker builds with non-root users, healthchecks, and
  `.dockerignore` files.
- Twelve-factor-style config via environment variables and Kubernetes
  ConfigMaps/Secrets.
- Liveness vs. readiness health-check separation, mirrored consistently
  across docker-compose, Kubernetes probes, and application code.
- Resource requests/limits on every Kubernetes workload.
- CI pipeline that tests, builds, and scans on every change — not just
  "it builds."
- Infrastructure and application manifests versioned in the same repo,
  reviewed the same way as application code.

## Security approach

- Containers run as non-root users.
- Dockerfiles linted with **hadolint**; images scanned with **Trivy**
  for known CVEs.
- Git history scanned for secrets with **gitleaks** on every CI run.
- Kubernetes `Secret` manifests in this repo are **placeholder examples
  only** (`secret.example.yaml`) — never real credentials. A later phase
  replaces them with a proper secrets-management approach.
- `.gitignore` explicitly blocks `.env` files, credentials, private keys,
  Terraform state, `.tfvars` files, and kubeconfig files from ever being
  committed. See [Security considerations](#security-considerations) below
  for the Terraform/AWS-specific details.

## Observability approach

- Both services expose `/health` (liveness) and `/ready` (readiness)
  endpoints.
- `task-service` exposes `/metrics` in Prometheus exposition format,
  including golden-signal HTTP metrics (traffic/errors/latency) for every
  route, added in Phase 5.
- A full Prometheus/Grafana/Loki/Alertmanager stack is configured under
  [observability/](observability/) and deployed via ArgoCD manifests under
  [argocd/](argocd/) - three custom alert-severity groups, three Grafana
  dashboards, and a log pipeline via Grafana Alloy. **Configured and
  validated, not installed onto a real cluster** - see [Observability
  (Phase 5)](#observability-phase-5) below for exactly what that means.
- `api-gateway` does not yet expose `/metrics` - a known limitation, see
  [observability/README.md#known-limitations](observability/README.md#known-limitations).

## Local development instructions

### Prerequisites
- Docker + Docker Compose
- (Optional, for manifest testing) a local Kubernetes cluster — kind,
  minikube, or Docker Desktop's built-in Kubernetes

### Run the full stack

```bash
cp .env.example .env
docker compose up --build
```

- Gateway: http://localhost:8080
- Backend (direct): http://localhost:8000
- API docs (FastAPI): http://localhost:8000/docs

### Try it out

```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Ship phase 1"}'

curl http://localhost:8080/api/tasks
```

Or run the smoke test against the running stack:

```bash
bash scripts/smoke-test.sh
```

### Run tests

```bash
make test            # both services
make test-gateway    # api-gateway only
make test-backend    # task-service only
```

### Try the Kubernetes manifests

See [kubernetes/README.md](kubernetes/README.md).

## AWS & Terraform infrastructure (Phase 2)

Terraform under [terraform/](terraform/) provisions the AWS infrastructure
needed to run TaskFlow on EKS: a VPC, IAM roles, and an EKS cluster with a
managed node group. **This phase only provisions infrastructure — it does
not deploy the Kubernetes manifests onto it.** See
[docs/aws-architecture.md](docs/aws-architecture.md) for the full
architecture diagram and component breakdown.

### AWS architecture

```
Internet
   │
   ▼
Internet Gateway
   │
   ▼
VPC (10.0.0.0/16)
 ├── Public subnets   → NAT Gateway, (later) public load balancers
 └── Private subnets  → EKS worker nodes only
        │
        ▼
   EKS control plane (managed by AWS)
        │
        ▼
   EKS managed node group
        │
        ▼
   (Phase 1's TaskFlow Kubernetes manifests would run here)
```

### Terraform architecture

```
terraform/
├── modules/
│   ├── vpc/    # VPC, subnets, IGW, NAT gateway(s), route tables
│   ├── iam/    # EKS cluster role + node role (no IAM users/access keys)
│   └── eks/    # EKS cluster, OIDC provider, managed node group
└── environments/
    └── dev/    # Composes the three modules for the dev environment
```

Three small, single-purpose modules rather than one large configuration:
each has a typed interface (variables in, outputs out), so a `staging` or
`prod` environment can reuse the exact same modules with different
variable values instead of duplicating resource definitions. See
[docs/aws-architecture.md](docs/aws-architecture.md#why-terraform-modules)
for the full reasoning, and [#why-worker-nodes-are-in-private-subnets](docs/aws-architecture.md#why-worker-nodes-are-in-private-subnets)
for why nodes never get a public IP.

### Configure AWS credentials

Never hardcode AWS credentials in Terraform files. Use one of:

```bash
# Option A: AWS CLI named profile (recommended)
aws configure --profile taskflow
export AWS_PROFILE=taskflow

# Option B: environment variables (e.g. from a password manager, not a file)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # if using temporary/SSO credentials

# Option C: AWS SSO
aws sso login --profile taskflow
export AWS_PROFILE=taskflow
```

Terraform's AWS provider picks up credentials from the environment/CLI
config automatically — no credentials are ever written into `.tf` files or
`terraform.tfvars`.

### Initialize, plan, apply, destroy

```bash
cd terraform/environments/dev

# One-time (or whenever modules/providers change)
terraform fmt -recursive        # from terraform/ to format the whole tree
terraform init

# Review your own variables (never commit terraform.tfvars)
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars as needed

terraform validate
terraform plan                  # review carefully before applying
terraform apply                 # provisions real AWS resources — costs money

# When you're done, avoid ongoing charges:
terraform destroy
```

No `terraform apply`/`destroy` is ever run automatically by CI — see
[.github/workflows/terraform.yml](.github/workflows/terraform.yml), which
only runs `fmt -check`, `init`, and `validate`.

### Estimated cost considerations

Nothing here is free — running this configuration incurs real AWS charges
for as long as it's applied:

| Resource | Approx. cost |
|---|---|
| EKS control plane | ~$0.10/hr (~$73/month) flat, regardless of cluster size |
| NAT Gateway | ~$0.045/hr (~$32/month) + ~$0.045/GB data processed (one NAT by default; see `single_nat_gateway`) |
| EC2 worker nodes | Depends on `node_instance_types` × `desired_node_count` (e.g. 2× `t3.medium` ≈ $60/month on-demand) |
| EBS volumes | `node_disk_size` GiB × node count (gp3 pricing) |
| CloudWatch Logs | Small — only `api`/`audit` log types enabled by default, 7-day retention |
| Data transfer | Variable, usually negligible for a demo workload |

**Run `terraform destroy` when you're not actively using the cluster** —
this is a portfolio project, not a production workload that needs to stay
up. `node_capacity_type = "SPOT"` and a smaller `desired_node_count` are
the easiest further cost levers (see `terraform.tfvars.example`).

### Security considerations

- No AWS access keys, secrets, or credentials are ever committed — see
  `.gitignore` (`*.tfstate`, `*.tfvars`, `.terraform/`, `*.pem`, `.env`,
  `credentials`), and the CI job never has AWS credentials configured at
  all.
- No IAM user or long-lived access key is created by this Terraform — only
  IAM *roles* assumable by AWS service principals (`eks.amazonaws.com`,
  `ec2.amazonaws.com`), following least-privilege via AWS-managed policies.
- Worker nodes run in private subnets with no public IPs (see below).
- The EKS API endpoint is public by default for a frictionless demo setup
  (`eks_public_access_cidrs = ["0.0.0.0/0"]`) — restrict this to your own
  IP/CIDR, or disable public access entirely, before treating this as
  anything beyond a personal sandbox.
- Terraform state (which can contain sensitive values in plan/apply
  output) stays local and gitignored by default; see
  `terraform/environments/dev/backend.tf` for how to move to encrypted S3
  remote state instead.

### Why worker nodes are placed in private subnets

Worker nodes never need to accept inbound connections from the internet —
the control plane reaches them over the VPC's private address space, and
their own outbound needs (image pulls, package updates) are satisfied by
the NAT gateway. Keeping them in private subnets means no node ever has a
public IP or an inbound-from-the-internet security group rule to justify,
and a compromised pod can't be reached directly — only whatever a
Kubernetes Service/Ingress explicitly exposes (which gets its own public
IP via the public subnets, not the node). See
[docs/aws-architecture.md](docs/aws-architecture.md#why-worker-nodes-are-in-private-subnets)
for the full explanation.

### Why Terraform modules are used

Splitting `vpc`, `iam`, and `eks` into separate modules gives each one a
small, explicit interface and keeps the blast radius of a change matching
the code you're reading — editing subnet logic means touching
`modules/vpc`, not a single large file that also defines IAM and EKS
resources. It also means a second environment (`staging`, `prod`) is a new
`environments/<name>` directory calling the same three modules with
different variables, not a copy-pasted configuration. See
[docs/aws-architecture.md](docs/aws-architecture.md#why-terraform-modules)
for more detail.

## Ansible configuration management & server automation (Phase 3)

Ansible under [ansible/](ansible/) configures the **operating system** on
a Linux server — a job Terraform (Phase 2) deliberately doesn't do.
Terraform provisions AWS infrastructure (networking, IAM, the EKS
cluster); Ansible then configures packages, timezone, an application
user, Docker, Node Exporter, and basic security hardening on a
general-purpose Ubuntu server reachable over SSH.

**Scope note:** this targets a standalone Ubuntu host (e.g. a bastion or
monitoring server) — **not** the EKS managed node group from Phase 2. EKS
worker nodes are provisioned and patched by AWS itself; Ansible is never
run against them here. See
[docs/ansible-architecture.md](docs/ansible-architecture.md) for the full
diagram and reasoning.

### Ansible architecture

```
ansible/
├── ansible.cfg
├── requirements.yml        # community.general collection
├── inventory/dev/          # placeholder host - see ansible/inventory/README.md
├── playbooks/
│   ├── site.yml             # common + docker + node_exporter + hardening
│   ├── configure_servers.yml
│   └── hardening.yml
└── roles/
    ├── common/               # packages, timezone, app user, MOTD
    ├── docker/               # Docker Engine + daemon config
    ├── node_exporter/        # pinned Node Exporter systemd service
    └── hardening/            # auto security updates, unneeded services off, opt-in SSH hardening
```

Full details — variables, running playbooks, check mode, linting,
idempotency, handlers, and security considerations — are in
[ansible/README.md](ansible/README.md).

### Terraform + Ansible relationship

```
Terraform → AWS infrastructure → Linux/compute → Ansible configuration
   → Docker / Node Exporter → Kubernetes/EKS → Helm + ArgoCD → Observability
```

Terraform models AWS infrastructure as a dependency graph tracked in
state; Ansible models the desired, idempotently-re-applied configuration
of an already-running machine. Neither is a good substitute for the
other — see
[docs/ansible-architecture.md](docs/ansible-architecture.md#why-terraform-and-ansible-not-just-one-tool)
for why this repo keeps them as two separate tools instead of leaning on
Terraform provisioners to configure servers.

### Security considerations

- The committed inventory (`ansible/inventory/dev/hosts.yml`) contains a
  placeholder host, never a real IP/hostname — see
  [ansible/inventory/README.md](ansible/inventory/README.md) for the
  gitignored `hosts.local.yml` pattern for pointing it at a real server.
- SSH-affecting hardening (`hardening_manage_ssh`) is **off by default**
  and validated with `sshd -t` before ever being installed — see
  [ansible/README.md](ansible/README.md#security-considerations).
- No AWS credential, IAM user, or long-lived secret is created or used by
  anything under `ansible/` — it only ever needs SSH key access to a
  Linux host.
- CI ([.github/workflows/ansible.yml](.github/workflows/ansible.yml))
  only runs `--syntax-check`, `ansible-lint`, and `ansible-inventory
  --graph` — it never connects to a real host and never runs a playbook
  for real.

## Helm + ArgoCD + GitOps delivery (Phase 4)

A Helm chart under [helm/taskflow/](helm/taskflow/) packages the Phase 1
application (api-gateway, task-service, PostgreSQL) for GitOps delivery,
and ArgoCD manifests under [argocd/](argocd/) declare how an
already-installed ArgoCD would deploy it onto the EKS cluster from Phase
2. **This phase is validated (`helm lint`/`helm template`/YAML
validation — see the Phase 4 implementation summary for exact commands
and results) but not deployed**: no image has been pushed to a real
registry, ArgoCD has not been installed anywhere, and nothing has been
applied to the real EKS cluster. See
[docs/gitops-architecture.md](docs/gitops-architecture.md) for the full
diagram and what's implemented vs. documented/future.

### The intended workflow

```
Developer pushes code
   |
   v
GitHub Actions (test / security scan / build image)
   |
   v
Container image
   |
   v                                    <- not yet wired up: push to a
GitOps manifest/chart update               real registry + commit the
   |                                       new tag back into Git (see
   v                                       docs/gitops-architecture.md)
ArgoCD detects the Git change
   |
   v
ArgoCD reconciles
   |
   v
EKS -> TaskFlow application
```

### Helm chart

Three components (api-gateway, task-service, PostgreSQL-as-StatefulSet),
one chart, driven by `values.yaml` + an environment overlay
(`values-dev.yaml` for a small lab environment; `values-prod.yaml` as a
documented, more conservative configuration *example* that nothing
deploys automatically). Reuses Phase 1's exact `/health`/`/ready`
endpoints for probes, and Phase 1's Dockerfiles' existing non-root users
for its security context. Full details:
[helm/taskflow/README.md](helm/taskflow/README.md).

### ArgoCD / GitOps

A dedicated `taskflow` `AppProject` (restricting source repo, destination
namespace, and resource kinds) plus one dev `Application` with automated
sync (`prune: true`, `selfHeal: true` — see
[argocd/README.md](argocd/README.md#sync-behavior) for exactly what those
mean and why they're appropriate for this low-stakes dev namespace, but
not something to copy onto a real production Application without
deciding that trade-off deliberately). Full details:
[argocd/README.md](argocd/README.md).

### Security considerations

- No image is pushed to a registry and no long-lived AWS/registry
  credential was added anywhere in this phase.
- No real password appears in `values-prod.yaml` — it uses the
  `existingSecret` pattern (a pre-created Kubernetes Secret referenced by
  name) instead. See
  [helm/taskflow/README.md](helm/taskflow/README.md#secrets).
- Image tags avoid `latest` throughout — the chart defaults to
  `.Chart.AppVersion`, and `.github/workflows/ci.yml`'s build job now
  also tags images with the commit SHA (still never pushed anywhere -
  see [docs/technology-decisions.md](docs/technology-decisions.md)).
- The ArgoCD `AppProject` restricts source repos, destination
  namespace, and resource kinds rather than granting unrestricted
  cluster permissions.

## Observability (Phase 5)

A Prometheus/Grafana/Loki/Alertmanager stack under
[observability/](observability/), deployed via three more ArgoCD
Applications under [argocd/](argocd/) into a dedicated `monitoring`
namespace - the same GitOps pattern Phase 4 established for the
application itself. **This phase is validated (`helm template` against
the real pinned chart versions, `promtool check rules`, `alloy validate`,
full JSON/YAML validation, and the complete task-service test suite - see
the Phase 5 implementation summary for every command and result) but not
deployed**: nothing here has been installed onto a real cluster, no
Prometheus has ever actually scraped anything, and no alert has ever
actually fired. See
[docs/observability-architecture.md](docs/observability-architecture.md)
for the full architecture (with Mermaid diagrams of the metrics and logs
data flows) and what's implemented vs. documented/future.

### What's in the stack

```
observability/
├── manifests/          # ServiceMonitor, PrometheusRule, Grafana dashboard ConfigMaps
├── prometheus/         # kube-prometheus-stack values (Prometheus + Grafana + Alertmanager + kube-state-metrics + node-exporter)
├── grafana/dashboards/ # 3 dashboards: TaskFlow Overview, Kubernetes Overview, Node/Infrastructure Overview
├── loki/                # log storage (SingleBinary mode)
└── alloy/               # log collector - see below for why Alloy, not Promtail
```

Pinned chart versions (verified via each chart repo's GitHub Releases API,
not recalled from memory - see
[observability/README.md#versions](observability/README.md#versions)):
`kube-prometheus-stack` 90.0.0, `loki` 7.3.0, `alloy` 1.12.1.

### Application metrics

Before this phase, only `/health` and `/ready` were instrumented -
task-service's real `/tasks` CRUD endpoints had no traffic/error/latency
metrics at all. This phase adds generic HTTP middleware
(`services/task-service/app/main.py`) covering every route, labeled by
**route template** (`/tasks/{task_id}`) rather than resolved path -
using the resolved path would create one Prometheus time series per task
UUID ever requested, an unbounded-cardinality label. See
[docs/observability-architecture.md#golden-signals](docs/observability-architecture.md#golden-signals).

### Why Alloy, not Promtail

Promtail (the log collector most existing Loki tutorials still show) is
in Grafana Labs' own maintenance-only mode, with Grafana Alloy as its
official, actively-developed replacement - this project builds the log
pipeline on Alloy instead. See
[observability/alloy/README.md](observability/alloy/README.md) for the
full pipeline explanation.

### Security considerations

- Prometheus, Alertmanager, Loki, and Grafana all default to `ClusterIP` -
  none are exposed publicly. See
  [observability/README.md#security](observability/README.md#security).
- No real secret is committed anywhere in this phase: Grafana's admin
  credentials use the same `existingSecret` pattern as Phase 4's Postgres
  password, and every Alertmanager receiver in the dev configuration is a
  safe, no-op placeholder with no delivery channel (Slack/webhook/email)
  configured at all. See
  [observability/README.md#secrets](observability/README.md#secrets).
- A dedicated `observability` AppProject (separate from `taskflow`'s)
  whitelists only the cluster-scoped resources (CRDs, ClusterRole/
  ClusterRoleBinding) this specific stack genuinely needs - verified by
  actually rendering the charts and inspecting their output, not guessed.
  See
  [argocd/README.md#observability-applications](argocd/README.md#observability-applications).

## Future implementation phases

- [x] **Phase 1 — Foundation**: application, Docker, docker-compose,
      Kubernetes manifests, GitHub Actions CI, security scanning basics.
- [x] **Phase 2 — Infrastructure as Code**: Terraform for AWS networking,
      IAM, and an EKS cluster (see [AWS & Terraform infrastructure](#aws--terraform-infrastructure-phase-2)
      above). Provisioning only — the cluster is not yet wired up to
      deploy Phase 1's manifests automatically.
- [x] **Phase 3 — Configuration management**: Ansible roles for base
      Linux config, Docker, Node Exporter, and opt-in security hardening
      on a standalone server (see
      [Ansible configuration management & server automation](#ansible-configuration-management--server-automation-phase-3)
      above). Targets a general-purpose Ubuntu host, not the EKS managed
      node group.
- [x] **Phase 4 — GitOps delivery**: a Helm chart for TaskFlow plus
      ArgoCD `AppProject`/`Application` manifests (see
      [Helm + ArgoCD + GitOps delivery](#helm--argocd--gitops-delivery-phase-4)
      above). Validated with `helm lint`/`helm template`/YAML
      validation — ArgoCD has not been installed anywhere and nothing
      has been deployed to a real cluster.
- [x] **Phase 5 — Observability**: Prometheus, Grafana, Loki, and
      Alertmanager (via kube-prometheus-stack + Loki + Grafana Alloy),
      wired to task-service's `/metrics` endpoint and new golden-signal
      HTTP metrics (see
      [Observability (Phase 5)](#observability-phase-5) above). Validated
      with `helm template`/`promtool check rules`/`alloy validate` -
      nothing has been installed onto a real cluster.
- [ ] **Phase 6 — Production concerns**: DNS, load balancing/ingress,
      TLS, and a documented production-troubleshooting runbook.

## Disclaimer

This is an original, personal portfolio project created to demonstrate
DevOps and platform engineering skills. It contains no code,
configuration, architecture, credentials, or proprietary information
from any employer or client project. All names, services, and
infrastructure described here are fictional and built solely for this
repository.
