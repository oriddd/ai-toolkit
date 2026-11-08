---
name: cd
description: >
  Java / Spring Boot Helm chart for Kubernetes — hardened security context, Actuator liveness/readiness probes, HPA,
  Prometheus ServiceMonitor, credentials Secret, umbrella-chart registry support. Use when adding or changing the
  Kubernetes/Helm deployment of a service.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [ci]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# CD Skill
This skill creates a `helm-chart/` directory at the repo root containing the
standard deployment manifests. **No environment-specific defaults are baked
in** — registries, shared ConfigMaps, runtime UID/GID conventions, etc. are
added as local overrides (your own `values.yaml` / values files per
environment), never in this shared skill.


```
helm-chart/
├── Chart.yaml
├── values.yaml
├── README.md
└── templates/
    ├── _helpers.tpl          # fullname, labels, serviceAccountName, credentialsSecretName
    ├── deployment.yaml
    ├── hpa.yaml
    ├── pdb.yaml              # only when autoscaling.minReplicas > 1
    ├── secret.yaml
    ├── service.yaml
    ├── serviceAccount.yaml
    └── servicemonitor.yaml
```

Every file except `Chart.yaml` and `README.md` has a template in [`templates/`](#templates) (`<file>.tmpl`).

## Rendering the templates (two steps)

The `.tmpl` files mix two kinds of `{{ }}`: **scaffold placeholders** (`{{chartName}}`, `{{appPort}}`,
`{{contextPath}}`, `{{autoscaling.maxReplicas}}` …, no spaces) and **Helm actions**, escaped as
`{{ "{{" }} .Values.x {{ "}}" }}` so they survive the first step. Render each file in this order:

1. **Substitute placeholders** — replace every `{{name}}` matching `\{\{[A-Za-z][\w.]*\}\}` with its input value
   (table below). Fail if a placeholder has no value.
2. **Unescape Helm** — replace the literal `{{ "{{" }}` with `{{` and `{{ "}}" }}` with `}}`.

```bash
# example for one file (inputs as KEY=VALUE pairs); do step 1 for every placeholder, then step 2
sed -e 's/{{chartName}}/my-service/g' -e 's/{{appPort}}/8080/g' … deployment.yaml.tmpl \
  | sed -e 's/{{ "{{" }}/{{/g' -e 's/{{ "}}" }}/}}/g' > helm-chart/templates/deployment.yaml
```

Do **not** render a `.tmpl` with Helm or Go templates directly (the placeholders are not valid actions), and do not
unescape before substituting. Check the result with `helm lint --strict helm-chart` and `helm template helm-chart`.

## Inputs (ask if missing)

| Variable | Example | Notes |
| --- | --- | --- |
| `chartName` | `my-service` | usually equals the repo / `artifactId` |
| `appPort` | `8080` | container port |
| `contextPath` | `/my-service` | Spring `server.servlet.context-path`; used by health probes. No trailing slash; empty string for the root (never `/`, which gives `//actuator/…`) |
| `imageRegistry` | `ghcr.io/<org>` | any OCI registry the cluster can pull from |
| `runAsUser` / `runAsGroup` | `1000` | non-root pod UID/GID, written into the template as `{{runAsUser}}` etc. Must equal the image's user and group (`ci` Dockerfile `adduser -u {{runAsUser}}`, `addgroup -g {{runAsGroup}}`) |
| `resources.requests` | `cpu: 500m`, `memory: 512Mi` | sensible defaults; tune per service |
| `resources.limits` | `cpu: 1`, `memory: 1Gi` | |
| `autoscaling.maxReplicas` | `5` | |
| `fsGroup` | `1000` | usually equals `runAsGroup` |

Set per environment in `values.yaml` (not scaffold placeholders): `extraEnv` (list of `{name, value}` or
`{name, valueFrom: {secretKeyRef: …}}`), `extraVolumes` / `extraVolumeMounts` (e.g. license files, fonts, certs),
`credentials.existingSecret`, `springProfilesActive` (default `k8s`, see `spring-boot-conventions`), `serviceMonitor.enabled`.

## Steps

1. **`Chart.yaml`** – `apiVersion: v2`, `type: application`, `version: 0.1.0`,
   `name` and `description` set to `chartName`, `appVersion` set to the release
   version (`1.4.0`, no `v` — `release-versioning` §6). The image tag defaults to
   `.Chart.AppVersion`.
2. **`values.yaml`** – Start from [`templates/values.yaml.tmpl`](./templates/values.yaml.tmpl)
   and prune sections that are not needed.
3. **`templates/deployment.yaml`** – Use [`templates/deployment.yaml.tmpl`](./templates/deployment.yaml.tmpl).
   Mandatory blocks (do not remove):
   - `securityContext` (`runAsNonRoot: true`, `runAsUser/Group`, `fsGroup`, seccomp `RuntimeDefault`).
   - Container-level `securityContext`: `allowPrivilegeEscalation: false`, drop ALL capabilities, `privileged: false`, `readOnlyRootFilesystem: true` (use an `emptyDir` for `/tmp` if the app writes temp files).
   - `enableServiceLinks: false`, `hostNetwork/PID/IPC: false`.
   - Startup + liveness + readiness probes on `{{contextPath}}/actuator/health/{liveness,readiness}` (liveness and readiness every 10 s so a hung pod is replaced in about 30 s).
   - `terminationGracePeriodSeconds: 60` and a native `preStop: { sleep: { seconds: 5 } }` (Kubernetes ≥ 1.30; works on
     distroless images without `sh`), so the pod drains before `SIGKILL`. Size the grace period with the
     `graceful-shutdown` budget (preStop + shutdown phases + executor waits).
   - A `/tmp` `emptyDir` — the template mounts it because the root filesystem is read-only.
   - `serviceAccountName` from the `serviceAccountName` helper (`serviceAccount.create` / `serviceAccount.name`).
   - Standard `app.kubernetes.io/*` labels and a release-scoped name (`fullname` helper), so two releases — or two
     services inside one umbrella chart — never collide.
   - `SPRING_PROFILES_ACTIVE` from `springProfilesActive`, and `extraEnv` / `extraVolumes` / `extraVolumeMounts` from values.
   - Pod-level `appArmorProfile: { type: RuntimeDefault }` (Kubernetes ≥ 1.30; replaces the deprecated `container.apparmor.security.beta.kubernetes.io/*` annotation).
   *(Add shared ConfigMaps as needed for your platform.)*
4. **Image registry** – `deployment.yaml` resolves the registry inline with
   `{{ (.Values.global).imageRegistry | default .Values.image.registry }}` so a parent
   (umbrella) chart can set it once for every service, and a standalone install
   falls back to the chart's own value. No registry helper is needed.
5. **`templates/service.yaml`** – ClusterIP service exposing port `http` → `appPort`.
6. **`templates/hpa.yaml`** – `autoscaling/v2` HorizontalPodAutoscaler tied to
   `.Values.autoscaling.{min,max}Replicas`, with
   `metrics: [{ type: Resource, resource: { name: cpu, target: { type: Utilization, averageUtilization: <targetCPUUtilizationPercentage> } } }]`
   (`targetCPUUtilizationPercentage` as a field exists only in `autoscaling/v1`). When `autoscaling.enabled` is false the
   Deployment sets `replicas: minReplicas` instead.
7. **`templates/serviceAccount.yaml`** – ServiceAccount (when `serviceAccount.create`), named by the helper,
   `automountServiceAccountToken: false` unless the service needs k8s API access.
8. **`templates/servicemonitor.yaml`** – Prometheus Operator `ServiceMonitor`
   scraping `{{contextPath}}/actuator/prometheus`. Guarded by
   `{{- if and .Values.serviceMonitor.enabled (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1/ServiceMonitor") }}`,
   so the chart installs on clusters without the Prometheus Operator. With `helm template` (GitOps), pass
   `--api-versions monitoring.coreos.com/v1/ServiceMonitor` where the operator exists.
9. **`templates/secret.yaml`** – `<fullname>-credentials` Secret rendered
   only when `credentials.values` is set and `credentials.existingSecret` is not (`{{- if … }}` guard). This is for
   dev/test only: in real environments point `credentials.existingSecret` at a Secret managed by External Secrets,
   Sealed Secrets or SOPS. The Deployment loads whichever Secret applies with `envFrom.secretRef`.
10. **`templates/pdb.yaml`** – PodDisruptionBudget (`maxUnavailable: 1`), rendered only when `autoscaling.minReplicas > 1`.

## Probes & observability contract

The service **must** expose:

- `GET {{contextPath}}/actuator/health/liveness`
- `GET {{contextPath}}/actuator/health/readiness`
- `GET {{contextPath}}/actuator/prometheus`

These are enabled in `application.yaml` (see `code-structure` skill) and
consumed by the Helm probes + ServiceMonitor.

Actuator shares `appPort` with the API, so the ingress / gateway **must deny** `{{contextPath}}/actuator/**` from
outside the cluster. Expose only `health`, `info` and `prometheus` by default; endpoints such as `httpexchanges`
(request headers) or `env` need that deny rule in place first.

## Do / Don't

✅ Keep secrets as `secretKeyRef` / `envFrom.secretRef` – never inline credentials in `values.yaml`
(`credentials.values` is for local/dev clusters only; real environments use `credentials.existingSecret`).
✅ Use `{{ (.Values.global).imageRegistry | default .Values.image.registry }}` for the
image registry so the chart works both standalone and inside an umbrella chart.
❌ Never set `runAsUser: 0`.
❌ Never expose the actuator port separately – it lives on the same `appPort`, and the ingress denies `/actuator/**`.
❌ Never bake environment-specific image registries, ConfigMaps, or service
discovery names into this skill — add them as local configuration values.

## Templates

Render with the [two-step process](#rendering-the-templates-two-steps).

- [`deployment.yaml.tmpl`](./templates/deployment.yaml.tmpl) — Hardened Deployment manifest.
- [`values.yaml.tmpl`](./templates/values.yaml.tmpl) — Baseline values for the chart.
- [`_helpers.tpl.tmpl`](./templates/_helpers.tpl.tmpl) — `fullname`, standard labels, ServiceAccount and Secret names.
- [`service.yaml.tmpl`](./templates/service.yaml.tmpl) — ClusterIP Service.
- [`hpa.yaml.tmpl`](./templates/hpa.yaml.tmpl) — `autoscaling/v2` HPA.
- [`pdb.yaml.tmpl`](./templates/pdb.yaml.tmpl) — PodDisruptionBudget when `minReplicas > 1`.
- [`serviceAccount.yaml.tmpl`](./templates/serviceAccount.yaml.tmpl) — ServiceAccount.
- [`servicemonitor.yaml.tmpl`](./templates/servicemonitor.yaml.tmpl) — CRD-guarded ServiceMonitor.
- [`secret.yaml.tmpl`](./templates/secret.yaml.tmpl) — dev/test credentials Secret.
