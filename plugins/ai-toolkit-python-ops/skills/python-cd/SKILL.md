---
name: python-cd
description: >
  Python / FastAPI Helm chart for Kubernetes — api and worker Deployments, Alembic migration hook Job, hardened
  security context, probes, HPA, PDB, ServiceMonitor, NetworkPolicy, OTel and proxy-header env. Use when deploying a
  Python service or worker to Kubernetes or changing its chart.
tier: should
applies_to: [rest, worker]
depends_on: [python-ci, python-graceful-shutdown]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python CD Skill
## When to use
When a Python service built by `python-ci` is deployed to Kubernetes, or when its chart, probes, scaling or
migration step change. The chart carries the shutdown budget of `python-graceful-shutdown`; it does not redefine it.

## Layout

```
helm-chart/
├── Chart.yaml
├── values.yaml                     # every per-environment knob; overridden per environment, never edited per deploy
└── templates/
    ├── _helpers.tpl                # names, labels, security contexts, shared env (settings, OTel)
    ├── deployment-api.yaml         # uvicorn: probes, preStop, FORWARDED_ALLOW_IPS
    ├── deployment-worker.yaml      # my-service-worker: heartbeat liveness, no Service (§4)
    ├── migration-job.yaml          # alembic upgrade head as a pre-install/pre-upgrade hook (§3)
    ├── service.yaml                # api only
    ├── serviceaccount.yaml
    ├── hpa.yaml                    # api only
    ├── pdb.yaml                    # api, only when it runs more than one replica
    ├── servicemonitor.yaml         # scrapes /metrics/ on the api
    └── networkpolicy.yaml          # api: ingress controller, monitoring, same namespace
```

**Helm, not plain manifests:** the migration must run once, before the new pods (a `pre-upgrade` hook does that
without pipeline code), the same chart serves every environment through values files, and `required` stops a
render that lacks a value that has no safe default. It mirrors the Java `cd` chart.

## Reference map
Load only the file you need.

| Section | Topic | Load when | File |
| --- | --- | --- | --- |
| all | Every chart file, verbatim (lint- and render-clean) | Creating or regenerating the chart | [references/chart.md](./references/chart.md) |

## 1. Values that differ per environment
```yaml
image: { repository: my-service, tag: "" }        # tag = the CI build (`python-ci`); defaults to appVersion
existingSecret: my-service-credentials            # DB_PASSWORD, tokens: created outside the chart
env:                                              # non-secret settings, read by pydantic-settings
  DB_URL: postgresql+asyncpg://app@postgres:5432/orders
forwardedAllowIps: ""                             # REQUIRED: ingress controller pod CIDR, never "*"
otel: { endpoint: "" }                            # empty = tracing off
```
- Settings arrive as environment variables with the names `python-code-structure` §5 reads (`DB_URL`,
  `DB_PASSWORD`, …). Secrets come only from `existingSecret` via `envFrom`; the chart never templates secret values.
- Non-secret settings are rendered inline into each pod (`app.env` helper), not into a chart ConfigMap: the
  migration hook runs before chart resources exist and needs them too.
- `FORWARDED_ALLOW_IPS` lets uvicorn's `--proxy-headers` (`python-ci` §3) trust `X-Forwarded-*` only from the
  ingress; the render fails without it (`python-security` §4).
- OTel: `OTEL_SERVICE_NAME` (`<release>-api` / `-worker`), `OTEL_EXPORTER_OTLP_ENDPOINT` only when set, and
  `OTEL_RESOURCE_ATTRIBUTES` with pod name, namespace and version. The tracing settings read `OTEL_SERVICE_NAME` and
  `OTEL_EXPORTER_OTLP_ENDPOINT` for `configure_tracing` (`python-observability` §3): an explicit `service.name` in
  `Resource.create` overrides the variable, so pass the variable's value, not a constant.

## 2. Hardened pods
Every pod (api, worker, migration) uses the same contexts:

```yaml
securityContext:                                  # pod
  runAsNonRoot: true
  runAsUser: 10001                                # the uid of the Dockerfile's `app` user
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile: { type: RuntimeDefault }
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
    volumeMounts: [{ name: tmp, mountPath: /tmp }] # tempfile, heartbeat files
volumes: [{ name: tmp, emptyDir: { sizeLimit: 64Mi } }]
```
- The image already compiles bytecode and sets `PYTHONDONTWRITEBYTECODE=1`, so a read-only root filesystem works;
  anything that must write uses `/tmp`.
- `automountServiceAccountToken: false` on the ServiceAccount and every pod: the service does not call the
  Kubernetes API. Set requests on CPU and memory and a memory limit; no CPU limit (throttling stretches latency).

## 3. Migrations: one hook Job per release
```yaml
metadata:
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          command: ["alembic", "upgrade", "head"]  # same image; alembic.ini in /app (`python-ci` §3)
```
- Runs once, before any new pod starts; a failed migration fails the release and the old pods keep serving.
- The Job uses no chart-created object (no ConfigMap, the namespace's default ServiceAccount without a token):
  hooks run before the release's resources exist. `existingSecret` therefore exists before the first install.
- Migrations stay compatible with the running version (add nullable → backfill → enforce, `python-persistence` §5),
  because old pods serve while the Job runs and during the rollout.
- Never `alembic upgrade` in the lifespan or an init container: every replica would race to migrate.

## 4. Api and worker Deployments
| | api | worker |
| --- | --- | --- |
| command | image `CMD` (uvicorn, `--proxy-headers`) | `["my-service-worker"]` |
| Service, HPA, PDB, ServiceMonitor | yes | no |
| liveness | `httpGet /health/live` | `exec ["python", "-m", "my_service.liveness"]` (heartbeat age) |
| readiness | `httpGet /health/ready` | none (no traffic to gate) |
| startup | `httpGet /health/live`, up to 60 s | `initialDelaySeconds: 30` on liveness |
| `preStop` | `sleep: { seconds: 5 }` | none |
| `terminationGracePeriodSeconds` | 45 | 40, with `DRAIN_SECONDS=20` |
| rollout | `maxUnavailable: 0, maxSurge: 1` | default |

- The budgets are `python-graceful-shutdown` §3 and §5: api `45 > 5 preStop + 20 uvicorn + 10 lifespan`;
  worker `40 > 20 drain + close`. Change a number there and here together, never one side.
- Worker liveness is the heartbeat probe of `python-graceful-shutdown` §5 (`HEARTBEAT_DIR=/tmp/heartbeat`,
  `HEARTBEAT_MAX_AGE_SECONDS`); keep the max age above the slowest record with retries.
- Workers scale by `replicas` up to the topic's partition count; no CPU HPA (an idle consumer burns no CPU while
  lag grows). Scale on lag with KEDA if needed.
- The api's liveness probe never checks dependencies: a database outage must not restart every pod.

## 5. Scaling, disruption, metrics and network
- HPA (`autoscaling/v2`) on CPU for the api, `minReplicas: 2`; the Deployment omits `replicas` when the HPA owns it.
- PDB `minAvailable: 1`, rendered only when the api runs more than one replica (a PDB on one replica blocks drains).
- ServiceMonitor scrapes `path: /metrics/` (the mounted app answers `/metrics` with a 307,
  `python-fastapi-conventions` §7). Without the Prometheus Operator set `metrics.serviceMonitor.enabled=false`.
- NetworkPolicy on the api pods: traffic only from the ingress controller's namespace, the monitoring namespace
  and pods of the same namespace. A NetworkPolicy cannot filter by path, so `/metrics` and `/docs` also stay off
  the Ingress rules (route only `/v1/...`).

## 6. Verify
```sh
helm lint --strict helm-chart --set forwardedAllowIps=10.0.0.0/8
helm template my-service helm-chart -n orders --set forwardedAllowIps=10.0.0.0/8 > /tmp/rendered.yaml
kubectl apply --dry-run=server -f /tmp/rendered.yaml   # only against a dev cluster you are allowed to use
```
Render with the values of every environment in CI; a missing `required` value fails the build, not the deploy.

## Do / Don't
- ✅ One image, three entrypoints: uvicorn, `my-service-worker`, `alembic upgrade head`.
- ✅ Hardened contexts on every pod, including the migration Job; `/tmp` as an `emptyDir`.
- ✅ Shutdown budgets copied from `python-graceful-shutdown`, written next to the numbers.
- ✅ Secrets only through `existingSecret`; `FORWARDED_ALLOW_IPS` set per cluster.
- ❌ `--forwarded-allow-ips='*'`, or no proxy-header trust at all behind an ingress.
- ❌ Migrations in the lifespan, an init container, or a Job without a hook (it races the rollout).
- ❌ A readiness probe or a Service on the worker; dependency checks in any liveness probe.
- ❌ `runAsUser: 0`, a writable root filesystem, or added capabilities.
- ❌ Secret values in `values.yaml` or the chart.

## Cross-references
- [`python-ci`](../python-ci/SKILL.md) — the image, its `CMD` and the uid the chart runs as.
- [`python-graceful-shutdown`](../python-graceful-shutdown/SKILL.md) — the budgets, preStop and the worker heartbeat.
- [`python-observability`](../python-observability/SKILL.md) — `/metrics`, OTel settings and log format.
- `python-security` — proxy headers, CORS and what stays off the public ingress.
- `python-persistence` — Alembic, `script_location` and forward-compatible migrations.
- `python-code-structure` — the settings classes the environment feeds.
