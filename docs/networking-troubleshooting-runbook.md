# Networking troubleshooting runbook (Phase 6)

Troubleshooting procedures for TaskFlow's external request path (DNS →
ALB → TLS → Ingress → api-gateway → task-service). Companion to
[docs/observability-runbook.md](observability-runbook.md), which covers
application/cluster-internal issues - this document is specifically about
everything on the path *into* the cluster.

**None of these have been exercised against a real domain, a real ALB, or
a real EKS cluster** - see
[docs/networking-architecture.md](networking-architecture.md) for exactly
what is and isn't deployed. This is written from a correct understanding
of the architecture, not lived experience with this specific deployment.

**Update (Phase 7):** the *Kubernetes-layer* mechanics behind
[#6](#6-ingress-exists-but-traffic-does-not-reach-service),
[#7](#7-service-exists-but-endpoints-are-empty), and
[#8](#8-pod-is-running-but-application-is-unreachable) were exercised for
real via ingress-nginx on a local cluster (not the AWS Load Balancer
Controller) - see
[docs/local-runtime-validation.md](local-runtime-validation.md). Every
AWS-specific scenario in this document (ALB, ACM, Route 53, CloudWatch)
remains genuinely untested - local ingress-nginx and a self-signed
certificate are not equivalent to those AWS components, and this document
does not claim otherwise.

Commands assume `kubectl` is already configured against the cluster
(`aws eks update-kubeconfig ...` - see the root README). AWS CLI commands
are documented for completeness but were not run against real
infrastructure - none of this project's validation required AWS
credentials.

## 1. DNS not resolving

**Symptoms:** `nslookup`/`dig api.taskflow.example.com` returns
`NXDOMAIN` or times out.

```bash
dig api.taskflow.example.com
dig api.taskflow.example.com @<a public resolver, e.g. 8.8.8.8>
```

**Likely causes:** the domain's registrar isn't delegated to the Route 53
hosted zone (missing/incorrect NS records at the registrar -
`terraform/modules/dns`'s `hosted_zone_name_servers` output, if
`create_hosted_zone = true`), the alias record was never created
(`create_alb_alias_record` defaults to `false` - see
[docs/networking-architecture.md#dns--route-53](networking-architecture.md#dns--route-53)),
or DNS propagation is still in progress after a recent change.

**Next step:** `aws route53 list-resource-record-sets --hosted-zone-id
<zone-id>` (documented here, not run - requires real AWS credentials and a
real zone) to confirm the record actually exists before assuming a
propagation delay.

## 2. DNS resolves but website is unreachable

**Symptoms:** `dig` returns an IP, but `curl` hangs or connection-refuses.

```bash
dig +short api.taskflow.example.com
curl -v https://api.taskflow.example.com
```

**Likely causes:** the DNS record points at an ALB that no longer exists
(a stale record - see [#16](#16-dns-points-to-old-load-balancer)), the
ALB's security group doesn't allow inbound 443 from the internet, or the
ALB has no healthy targets at all (see
[#5](#5-alb-exists-but-target-is-unhealthy)).

**Next step:** `kubectl get ingress -n taskflow -o wide` - confirms the
Ingress's own `ADDRESS` column matches what DNS resolves to.

## 3. HTTP works but HTTPS fails

**Symptoms:** port 80 responds, port 443 times out or connection-resets.

**Likely causes:** the ALB's HTTPS listener (port 443) was never created
- check `alb.ingress.kubernetes.io/listen-ports` actually includes
`{"HTTPS": 443}` (see `helm/taskflow/templates/ingress.yaml`) - or the
ALB's security group blocks 443 specifically while allowing 80.

```bash
kubectl describe ingress -n taskflow
```

Look for the controller's own events on the Ingress object - a failure to
create the HTTPS listener (e.g. because the certificate ARN is invalid)
shows up here.

## 4. HTTPS certificate error

**Symptoms:** browser/`curl` reports a certificate mismatch, expiry, or
untrusted-issuer error.

```bash
curl -vI https://api.taskflow.example.com 2>&1 | grep -A5 "SSL certificate"
openssl s_client -connect api.taskflow.example.com:443 -servername api.taskflow.example.com </dev/null 2>/dev/null | openssl x509 -noout -dates -subject
```

**Likely causes:** `apiGateway.ingress.certificateArn` points at a
certificate for the wrong domain (a copy-paste error, or the certificate
was issued for a different `subject_alternative_names` set - see
`terraform/modules/dns/main.tf`), the certificate is still `PENDING_VALIDATION`
(the DNS validation records haven't propagated/been created yet - see
[#17](#17-tls-certificate-renewalvalidation-issue)), or it's genuinely
expired (ACM auto-renews, but only while the validation records remain in
the zone - see docs/networking-architecture.md#tls--acm).

## 5. ALB exists but target is unhealthy

**Symptoms:** the ALB responds but every request gets a 502/503; AWS
console (or `aws elbv2 describe-target-health`, documented here, not run)
shows targets as `unhealthy`.

```bash
kubectl get pods -n taskflow -o wide
kubectl -n taskflow exec -it <api-gateway-pod> -- wget -qO- http://localhost:8080/health
```

**Likely causes:** the ALB's health-check path/port doesn't match
`apiGateway.ingress.healthCheckPath` (`/health` by default) or the actual
container port, the security group the ALB creates for pod-targeting
traffic isn't allowing traffic to the node/pod ENI, or the pod itself is
failing its OWN readiness probe (see
[docs/observability-runbook.md#5-pod-not-ready](observability-runbook.md#5-pod-not-ready)
- a Kubernetes-readiness-probe failure and an ALB-target-health failure
are two different systems checking similar things and can disagree).

## 6. Ingress exists but traffic does not reach service

**Symptoms:** `kubectl get ingress` shows the Ingress with an address, but
requests never reach any pod (no matching lines in `kubectl logs`).

```bash
kubectl get ingress -n taskflow
kubectl describe ingress -n taskflow
kubectl get svc -n taskflow
kubectl get endpoints -n taskflow
```

**Likely causes:** the Ingress's backend `service.name`/`service.port`
doesn't match the actual Service (a typo, or the Service was renamed -
compare `helm/taskflow/templates/ingress.yaml`'s backend against
`api-gateway-service.yaml`), the Service's `endpoints` list is empty (see
[#7](#7-service-exists-but-endpoints-are-empty)), or `ingressClassName:
alb` doesn't match an actual `IngressClass` (see
[#8 in the observability
runbook](observability-runbook.md) for the analogous ServiceMonitor
selector-mismatch pattern - same root cause shape, different resource).

## 7. Service exists but endpoints are empty

**Symptoms:** `kubectl get endpoints <service> -n taskflow` shows no
addresses.

```bash
kubectl get endpoints api-gateway -n taskflow
kubectl get endpointslices -n taskflow -l app.kubernetes.io/name=api-gateway
kubectl get pods -n taskflow -l app.kubernetes.io/name=api-gateway --show-labels
```

**Likely causes:** the Service's `spec.selector` doesn't match any
running pod's labels (compare against the Deployment's
`spec.template.metadata.labels` - both come from the same
`taskflow.selectorLabels` helper in this chart, so this specific mismatch
would indicate a real chart bug rather than a values misconfiguration),
or there simply are no `Ready` pods at all (an empty endpoints list is the
*expected*, correct state when every pod is failing readiness - see
[docs/observability-runbook.md#5-pod-not-ready](observability-runbook.md#5-pod-not-ready)).

## 8. Pod is running but application is unreachable

**Symptoms:** `kubectl get pods` shows `Running`/`Ready`, but the app
still doesn't respond.

```bash
kubectl -n taskflow port-forward pod/<pod-name> 8080:8080
curl http://localhost:8080/health
```

**Likely causes:** the container is listening on a different port than
the Service/Ingress expects (check `containerPort` in
`api-gateway-deployment.yaml` against `apiGateway.service.port`), a
`NetworkPolicy` is blocking traffic that would otherwise reach the pod
(see [#11](#11-kubernetes-networkpolicy-blocks-traffic)), or the
port-forward test above succeeding while the Service-level test fails
narrows the problem to the Service/Ingress layer specifically rather than
the application itself.

## 9. api-gateway cannot reach task-service

**Symptoms:** api-gateway's `/ready` returns `503` with `"reason"`
mentioning a connection failure (see `services/api-gateway/src/app.js`),
or `/api/*` requests all fail.

```bash
kubectl -n taskflow exec -it <api-gateway-pod> -- wget -qO- http://task-service:8000/health
kubectl get svc task-service -n taskflow
kubectl get endpoints task-service -n taskflow
kubectl get networkpolicy -n taskflow
```

**Likely causes:** `TASK_SERVICE_URL` (an env var from
`task-service-deployment.yaml`... actually set on api-gateway's own
Deployment/ConfigMap - see `helm/taskflow/values.yaml`) doesn't match
task-service's actual Service DNS name, task-service has no `Ready` pods
(see [#7](#7-service-exists-but-endpoints-are-empty)), or (if
`global.networkPolicy.enabled: true`) the api-gateway->task-service egress
rule doesn't match task-service's actual pod labels - see
`helm/taskflow/templates/networkpolicy.yaml`.

## 10. task-service cannot reach PostgreSQL

**Symptoms:** task-service's `/ready` returns `503` ("database
unavailable" - see `services/task-service/app/main.py`).

```bash
kubectl -n taskflow exec -it <task-service-pod> -- python -c "import socket; socket.create_connection(('postgres', 5432), timeout=3)"
kubectl get pods -n taskflow -l app.kubernetes.io/name=postgres
kubectl logs -n taskflow -l app.kubernetes.io/name=postgres --tail=100
```

**Likely causes:** the postgres pod itself is down/crash-looping (check
its own logs directly - a bad `POSTGRES_PASSWORD`/`existingSecret`
mismatch is a common cause, see
`helm/taskflow/README.md#secrets`), `DATABASE_URL` doesn't match
postgres's actual Service name/credentials, or (if NetworkPolicy is
enabled) the task-service->postgres egress rule / postgres's own ingress
rule doesn't match.

## 11. Kubernetes NetworkPolicy blocks traffic

**Symptoms:** a connection that should work (per the diagrams in
[docs/networking-architecture.md#2-internal-service-communication](networking-architecture.md#2-internal-service-communication))
fails only when `global.networkPolicy.enabled: true`, and works again
when it's set back to `false`.

```bash
kubectl get networkpolicy -n taskflow
kubectl describe networkpolicy <name> -n taskflow
```

**Likely causes:** a label mismatch between a NetworkPolicy's
`podSelector`/`from`/`to` and the actual pod/namespace labels (the
namespace-level rules use the automatic
`kubernetes.io/metadata.name` label - confirm the monitoring namespace is
actually named `monitoring`, matching
`global.networkPolicy.monitoringNamespace`), or - the far more common
case in practice - **the CNI isn't enforcing NetworkPolicy at all**, in
which case this specific symptom (works/doesn't-work toggling with the
flag) would NOT occur, since an unenforced policy has no effect either
way. See
[docs/networking-architecture.md#network-policies](networking-architecture.md#network-policies)
for that enforcement assumption.

## 12. Intermittent 502/503 errors

**Symptoms:** most requests succeed; a small percentage return 502/503.

**Likely causes:** a rolling deployment briefly removing a pod from the
target group before the ALB's own health check notices (a normal,
expected blip - compare timing against `kubectl rollout history`), pods
being OOMKilled/restarting under load (see
[docs/observability-runbook.md#4-pod-restarting](observability-runbook.md#4-pod-restarting)),
or the ALB's deregistration delay being shorter than a request's actual
duration during scale-down.

**Relevant signal:** Grafana's TaskFlow Overview dashboard's "Errors -
5xx ratio" panel (see
[docs/observability-architecture.md#golden-signals](observability-architecture.md#golden-signals))
- a sustained low-level 5xx rate correlating with deployment timestamps
points at the rolling-update explanation; a rate correlating with traffic
spikes points at capacity instead.

## 13. High latency at load balancer

**Symptoms:** requests are slow specifically when going through the ALB,
but fast when port-forwarded directly to a pod.

**Likely causes:** the ALB itself is under-provisioned for a sudden
traffic spike (ALBs scale automatically but not instantaneously), a
security group or NACL is causing retransmits, or - most likely for a
project this size - the "slowness" is actually happening in
task-service/Postgres and the ALB is just faithfully reporting it (rule
out with the direct port-forward comparison above).

**Relevant signal:** compare the TaskFlow Overview dashboard's "Latency -
p50/p95" panel (application-measured) against AWS's own ALB latency
metric (not collected in this project - see
[docs/networking-architecture.md#ingress-observability](networking-architecture.md#ingress-observability))
- if application-measured latency is low but the client still experiences
slowness, the gap is happening between the client and the pod, i.e. at
the ALB/network layer.

## 14. ALB health checks failing

**Symptoms:** same as [#5](#5-alb-exists-but-target-is-unhealthy) - listed
separately here because the fix differs depending on *why*.

```bash
kubectl -n taskflow exec -it <api-gateway-pod> -- wget -S -O- http://localhost:8080/health
```

**Likely causes:** the health-check path returns a non-200 (check
`apiGateway.ingress.healthCheckPath` matches a route that actually
returns 200 - `/health` always does per Phase 1's implementation, unless
overridden), the health-check protocol/port annotation doesn't match the
container's actual listening port, or the success-codes annotation
(`alb.ingress.kubernetes.io/success-codes: "200"`) is stricter than what
the endpoint actually returns.

## 15. Application returns 5xx

**Symptoms:** the request reaches the application (not a
networking/routing failure), which itself returns a 5xx.

This is an **application** issue, not a networking one - see
[docs/observability-runbook.md#2-high-http-error-rate](observability-runbook.md#2-high-http-error-rate)
for the full procedure. Included here only to make the distinction
explicit: a 5xx from api-gateway/task-service itself looks identical to a
client as a 5xx from the ALB (e.g. a failed health check), but the
troubleshooting paths are completely different - `kubectl logs` shows
which one you actually have.

## 16. DNS points to old load balancer

**Symptoms:** DNS resolves, but to an ALB that no longer exists or has
been replaced (e.g. after recreating the Ingress/controller).

```bash
dig +short api.taskflow.example.com
kubectl get ingress -n taskflow -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

Compare the two - a mismatch confirms a stale alias record.

**Likely causes:** the Route 53 alias record
(`terraform/modules/dns`'s `aws_route53_record.alb_alias`, when
`create_alb_alias_record = true`) was never updated after the ALB was
recreated - this is exactly the manual/opt-in step
[docs/networking-architecture.md#production-vs-portfolio](networking-architecture.md#production-vs-portfolio)
notes `external-dns` would automate in a production setup. Fix: re-run
`terraform apply` with the new `alb_dns_name`/`alb_zone_id`, or adopt
`external-dns`.

## 17. TLS certificate renewal/validation issue

**Symptoms:** a certificate that was previously valid now shows as
`PENDING_VALIDATION` or expired.

```bash
aws acm describe-certificate --certificate-arn <arn>   # documented, not run - requires real AWS credentials
```

**Likely causes:** the DNS validation CNAME records
(`terraform/modules/dns`'s `aws_route53_record.cert_validation`) were
deleted or modified out-of-band (e.g. someone manually "cleaned up" DNS
records that looked unused) - ACM can only auto-renew while these remain
in place. Fix: `terraform plan`/`apply` against the dns module to restore
them (Terraform will detect and recreate the drifted records), then wait
for ACM to re-validate.
