# Kubernetes manifests (local testing)

Plain manifests for trying the platform on a local cluster (kind, minikube,
Docker Desktop). No Helm/Kustomize yet — that's introduced once there are
multiple environments to manage (see the repo root README's roadmap).

## Apply order

```bash
kubectl apply -f kubernetes/namespace.yaml

kubectl apply -f kubernetes/postgres/secret.example.yaml
kubectl apply -f kubernetes/postgres/configmap.yaml
kubectl apply -f kubernetes/postgres/deployment.yaml
kubectl apply -f kubernetes/postgres/service.yaml

kubectl apply -f kubernetes/task-service/secret.example.yaml
kubectl apply -f kubernetes/task-service/configmap.yaml
kubectl apply -f kubernetes/task-service/deployment.yaml
kubectl apply -f kubernetes/task-service/service.yaml

kubectl apply -f kubernetes/api-gateway/configmap.yaml
kubectl apply -f kubernetes/api-gateway/deployment.yaml
kubectl apply -f kubernetes/api-gateway/service.yaml
```

Or simply: `kubectl apply -R -f kubernetes/`

## Notes

- `secret.example.yaml` files contain **placeholder values only** and are
  safe to keep in version control. Replace them locally (or via a real
  secrets manager in later phases) before applying to a shared cluster.
- Postgres uses `emptyDir` storage, which is not durable across pod
  restarts — fine for local demos, not for anything else.
- Images are referenced as `taskflow/*:latest`; build them locally first
  (`docker compose build`) and load them into your local cluster (e.g.
  `kind load docker-image`) since there is no registry push in Phase 1.
- To reach the gateway locally: `kubectl port-forward -n taskflow svc/api-gateway 8080:8080`.
