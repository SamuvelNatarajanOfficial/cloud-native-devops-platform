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
  containers → Kubernetes → Terraform/AWS/EKS → GitOps (ArgoCD) →
  observability (Prometheus/Grafana/Loki/Alertmanager).
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
| CI/CD              | GitHub Actions                                 |
| Security scanning  | hadolint, Trivy, gitleaks                      |
| *Planned*          | Ansible, Helm, ArgoCD, Prometheus, Grafana, Loki, Alertmanager |

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

Not fully built out yet — this is a deliberately staged project. What's
already in place:

- Both services expose `/health` (liveness) and `/ready` (readiness)
  endpoints.
- `task-service` exposes `/metrics` in Prometheus exposition format.

Planned: a Prometheus/Grafana/Loki/Alertmanager stack (see roadmap below)
that scrapes these endpoints and gives this platform real dashboards and
alerts.

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

## Future implementation phases

- [x] **Phase 1 — Foundation**: application, Docker, docker-compose,
      Kubernetes manifests, GitHub Actions CI, security scanning basics.
- [x] **Phase 2 — Infrastructure as Code**: Terraform for AWS networking,
      IAM, and an EKS cluster (see [AWS & Terraform infrastructure](#aws--terraform-infrastructure-phase-2)
      above). Provisioning only — the cluster is not yet wired up to
      deploy Phase 1's manifests automatically.
- [ ] **Phase 3 — Configuration management**: Ansible for anything not
      natively managed by Kubernetes.
- [ ] **Phase 4 — GitOps delivery**: ArgoCD reconciling this repo's
      manifests (via Helm charts) onto the EKS cluster.
- [ ] **Phase 5 — Observability**: Prometheus, Grafana, Loki, and
      Alertmanager, wired to the `/metrics` endpoints already in place.
- [ ] **Phase 6 — Production concerns**: DNS, load balancing/ingress,
      TLS, and a documented production-troubleshooting runbook.

## Disclaimer

This is an original, personal portfolio project created to demonstrate
DevOps and platform engineering skills. It contains no code,
configuration, architecture, credentials, or proprietary information
from any employer or client project. All names, services, and
infrastructure described here are fictional and built solely for this
repository.
