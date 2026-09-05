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
| CI/CD              | GitHub Actions                                 |
| Security scanning  | hadolint, Trivy, gitleaks                      |
| *Planned*          | Terraform, Ansible, AWS/EKS, Helm, ArgoCD, Prometheus, Grafana, Loki, Alertmanager |

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
  Terraform state, and kubeconfig files from ever being committed.

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

## Future implementation phases

- [x] **Phase 1 — Foundation**: application, Docker, docker-compose,
      Kubernetes manifests, GitHub Actions CI, security scanning basics.
- [ ] **Phase 2 — Infrastructure as Code**: Terraform for AWS networking,
      IAM, and an EKS cluster.
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
