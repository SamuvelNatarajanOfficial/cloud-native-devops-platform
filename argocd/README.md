# ArgoCD (Phase 4)

Manifests for deploying TaskFlow's Helm chart ([../helm/taskflow/](../helm/taskflow/))
via ArgoCD/GitOps. **Nothing in this directory has been applied to a real
cluster from this repository** — see the root Phase 4 summary's "AWS
changes" and "Kubernetes validation" sections for exactly what was and
wasn't done. This README documents how a reviewer (or you, later) would
actually do it.

## Contents

```
argocd/
├── namespace.yaml         # the "argocd" namespace ArgoCD itself runs in
├── project.yaml            # a dedicated AppProject scoping what taskflow-dev can touch
├── application-dev.yaml     # the Application - points at helm/taskflow + values-dev.yaml
└── README.md                # this file
```

There is deliberately no `application-prod.yaml` — `values-prod.yaml` is
a documented configuration example, not something this repo deploys (see
its own header comment and `helm/taskflow/README.md`).

## Installing ArgoCD

This repo does **not** vendor ArgoCD's own install manifest (it's large
and changes often — better to always install the current, official one).
Official method:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for it to come up:
kubectl -n argocd get pods -w
```

(`argocd/namespace.yaml` in this repo is equivalent to the
`kubectl create namespace argocd` step above, if you'd rather apply it
from a file already in version control.)

Access the UI/CLI (no Ingress/LoadBalancer assumed — port-forward is the
zero-extra-setup option):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Get the initial admin password (rotate/replace this — it's meant to be
changed on first login, not left as-is):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Full official docs: https://argo-cd.readthedocs.io/en/stable/getting_started/

## Creating the project

```bash
kubectl apply -f argocd/project.yaml
```

`project.yaml` defines a dedicated `taskflow` `AppProject` restricting:

- **Source repositories** — only this repo's URL (or your own fork's, if
  you change it)
- **Destination** — only the in-cluster API server
  (`https://kubernetes.default.svc`) and only the `taskflow` namespace
- **Resource kinds** — an explicit whitelist of the exact Kinds this
  chart creates (Deployment, StatefulSet, Service, ConfigMap, Secret,
  PVC), not a blanket allow-all, and **no** cluster-scoped resources at
  all (`clusterResourceWhitelist: []`)

This means even a misconfigured `Application` in this project can't
accidentally target a different cluster, a different namespace, or
create some unrelated cluster-scoped resource.

## Creating the application

```bash
kubectl apply -f argocd/application-dev.yaml
```

`application-dev.yaml`'s `source` points at:

```yaml
source:
  repoURL: https://github.com/SamuvelNatarajanOfficial/cloud-native-devops-platform.git
  targetRevision: main
  path: helm/taskflow
  helm:
    valueFiles:
      - values-dev.yaml
```

If you're working from your own fork, update `repoURL` here **and** in
`argocd/project.yaml`'s `sourceRepos` (both must match, or ArgoCD refuses
the Application).

## Connecting Git

No credentials are needed for a **public** repository like this one —
ArgoCD reads it anonymously over HTTPS, exactly as configured above.
Nothing in this repo configures a private-repo credential (SSH key or
token) — see `argocd/README.md`'s own rule and the root Phase 4 summary's
"Secrets" section. If you fork this to a private repo, you'd add a
repository credential via `argocd repo add` or a `Secret` labeled
`argocd.argoproj.io/secret-type: repository` — **never commit that
Secret's contents to Git.**

## Sync behavior

`application-dev.yaml` enables automated sync:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

- **`prune: true`** — resources removed from Git (e.g. you delete a
  template) are also deleted from the cluster. Without this, Git would
  stop being a *complete* description of what's deployed — deleted
  templates would leave orphaned resources running forever.
- **`selfHeal: true`** — a change made directly against the cluster
  (`kubectl edit`, `kubectl scale`, etc.) that doesn't match Git is
  reverted back to what Git says, on the next reconciliation. This is
  what actually makes Git the source of truth instead of just a
  suggestion.
- **`CreateNamespace=true`** — creates the `taskflow` namespace via
  ArgoCD's own pre-sync mechanism, matching
  `helm/taskflow`'s `global.createNamespace: false` (see that chart's
  README for why the chart itself doesn't create it).

Both `prune` and `selfHeal` are enabled here specifically **because**
this is a low-stakes dev/lab namespace where every possible action
(reapplying this chart's own declared state) is already fully described
in this same Git repo — there's no scenario where "ArgoCD reverted my
manual change" is surprising or destructive beyond what a `git diff`
already shows. **Do not copy this same policy onto a real production
Application without deciding that trade-off deliberately** — e.g. you may
want `selfHeal: false` (see, but don't auto-revert) while a human
confirms an emergency `kubectl` change was intentional before it's
committed back to Git.

## Checking application health

```bash
argocd app get taskflow-dev
argocd app list
# or, without the ArgoCD CLI:
kubectl -n argocd get application taskflow-dev -o yaml
```

ArgoCD reports two independent states worth understanding:

- **Sync status** (`Synced`/`OutOfSync`) — does the live cluster match
  Git?
- **Health status** (`Healthy`/`Progressing`/`Degraded`/`Missing`) — are
  the resources themselves working (e.g. a Deployment's pods actually
  `Ready`)? A sync can succeed (`Synced`) while the app is still
  `Progressing` or even `Degraded` if, say, the image can't be pulled.

## Viewing sync history

```bash
argocd app history taskflow-dev
```

Each entry ties a deployed revision back to the exact Git commit SHA that
produced it — this is the audit trail GitOps gives you for free (see
`docs/gitops-architecture.md`'s "Auditability" section).

## Rollback

Two ways, and they're not quite the same thing:

```bash
# ArgoCD-native: re-deploy a specific prior sync from `history` above.
# This changes what's LIVE, but is a cluster-side operation - it does
# not, by itself, change what Git says (the next automated sync could
# put you right back where you started unless selfHeal considers this
# rollback itself the new desired state, which it does NOT - a rollback
# via this command is inherently a manual, one-off deviation from Git).
argocd app rollback taskflow-dev <historyId>

# GitOps-native (preferred): revert the Git commit that caused the
# problem, and let ArgoCD reconcile the reverted state automatically.
# This keeps Git and the cluster in agreement, and leaves the same PR-
# reviewable audit trail every other change does.
git revert <bad-commit>
git push
```

**Neither of these was exercised in this phase** — no ArgoCD was
installed anywhere, and no `helm install` was run against any cluster
either (see the root Phase 4 summary for exactly what validation *was*
performed: `helm lint`/`helm template`, not a real release). `helm
rollback`/`helm history` (see `helm/taskflow/README.md#rollback`) is the
underlying mechanism ArgoCD itself uses for a Helm-sourced Application,
but that's a description of how it works, not a claim that it was tested
here.

## Deleting the application

```bash
# Removes the Application; add --cascade to also delete everything it
# deployed (omit it to leave the deployed resources in place, "orphaned"
# from ArgoCD's perspective but still running):
argocd app delete taskflow-dev --cascade

# Or declaratively:
kubectl delete -f argocd/application-dev.yaml
```

## How this fits with Helm/Terraform

See [docs/gitops-architecture.md](../docs/gitops-architecture.md) for the
full diagram: Terraform (Phase 2) provisions the EKS cluster this would
run on; Helm (this phase) packages the application; ArgoCD (this phase)
is the mechanism that would keep a real cluster's state matching this
Git repo, once installed.
