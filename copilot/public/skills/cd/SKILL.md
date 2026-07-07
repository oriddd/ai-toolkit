---
name: cd
description: Generate a vendor-neutral Helm chart to deploy a Java/Spring Boot microservice to Kubernetes, with hardened security context, liveness/readiness probes on Actuator, an HPA, a ServiceMonitor for Prometheus, and a credentials Secret. Organization-specific image registries, shared ConfigMaps, and platform integrations should be added as local overrides.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [ci]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# CD Skill (public)

This skill creates a `helm-chart/` directory at the repo root containing the
standard deployment manifests. **No organization-specific defaults are baked
in** — registries, shared ConfigMaps, runtime UID/GID conventions, etc. are


```
helm-chart/
├── Chart.yaml
├── values.yaml
├── README.md
└── templates/
    ├── _helper.tpl
    ├── deployment.yaml
    ├── hpa.yaml
    ├── secret.yaml
    ├── service.yaml
    ├── serviceAccount.yaml
    └── servicemonitor.yaml
```

## Inputs (ask if missing)

| Variable | Example | Notes |
| --- | --- | --- |
| `chartName` | `my-service` | usually equals the repo / `artifactId` |
| `appPort` | `8080` | container port |
| `contextPath` | `/my-service` | Spring `server.servlet.context-path`; used by health probes |
| `imageRegistry` | `ghcr.io/<org>` | any OCI registry the cluster can pull from |
| `runAsUser` / `runAsGroup` / `fsGroup` | `1000` | non-root pod UID/GID (organization may override) |
| `resources.requests` | `cpu: 500m`, `memory: 512Mi` | sensible defaults; tune per service |
| `resources.limits` | `cpu: 1`, `memory: 1Gi` | |
| `autoscaling.maxReplicas` | `5` | |
| `extraEnv` | list of `{name, value}` or `{name, secretKeyRef}` | service-specific env vars |
| `extraVolumes` / `extraVolumeMounts` | optional | e.g. license files, fonts, certs |

## Steps

1. **`Chart.yaml`** – `apiVersion: v2`, `type: application`, `version: 0.1.0`,
   `name` and `description` set to `chartName`.
2. **`values.yaml`** – Start from [`templates/values.yaml.tmpl`](./templates/values.yaml.tmpl)
   and prune sections that are not needed.
3. **`templates/deployment.yaml`** – Use [`templates/deployment.yaml.tmpl`](./templates/deployment.yaml.tmpl).
   Mandatory blocks (do not remove):
   - `securityContext` (`runAsNonRoot: true`, `runAsUser/Group`, `fsGroup`, seccomp `RuntimeDefault`).
   - Container-level `securityContext`: `allowPrivilegeEscalation: false`, drop ALL capabilities, `privileged: false`, `readOnlyRootFilesystem: true` (use an `emptyDir` for `/tmp` if the app writes temp files).
   - `enableServiceLinks: false`, `hostNetwork/PID/IPC: false`.
   - Liveness + readiness probes on `{{contextPath}}/actuator/health/{liveness,readiness}`.
   - `serviceAccountName: {{ .Chart.Name }}`.
   *(Add AppArmor annotations or shared ConfigMaps as needed for your platform.)*
4. **`templates/_helper.tpl`** – Always include the `helper.images.registryName`
   helper so umbrella charts can override via `.Values.global.imageRegistry`.
5. **`templates/service.yaml`** – ClusterIP service exposing port `http` → `appPort`.
6. **`templates/hpa.yaml`** – HorizontalPodAutoscaler tied to
   `.Values.autoscaling.{min,max}Replicas` and `targetCPUUtilizationPercentage`.
7. **`templates/serviceAccount.yaml`** – ServiceAccount named `{{ .Chart.Name }}`,
   `automountServiceAccountToken: false` unless the service needs k8s API access.
8. **`templates/servicemonitor.yaml`** – Prometheus Operator `ServiceMonitor`
   scraping `{{contextPath}}/actuator/prometheus`.
9. **`templates/secret.yaml`** – `{{ .Chart.Name }}-credentials` Secret rendered
   only when the relevant value is non-null (use `{{- if … }}` guards).

## Probes & observability contract

The service **must** expose:

- `GET {{contextPath}}/actuator/health/liveness`
- `GET {{contextPath}}/actuator/health/readiness`
- `GET {{contextPath}}/actuator/prometheus`

These are enabled in `application.yaml` (see `code-structure` skill) and
consumed by the Helm probes + ServiceMonitor.

## Do / Don't

✅ Keep secrets as `secretKeyRef` – never inline credentials in `values.yaml`.
✅ Use `{{ include "helper.images.registryName" . }}` for the image registry so
the chart works both standalone and inside an umbrella chart.
❌ Never set `runAsUser: 0`.
❌ Never expose the actuator port separately – it lives on the same `appPort`.
❌ Never bake organization-specific image registries, ConfigMaps, or service
discovery names into this skill — add them as local configuration values.

## 4. Templates

- [`deployment.yaml.tmpl`](./templates/deployment.yaml.tmpl) — Hardened Deployment manifest.
- [`values.yaml.tmpl`](./templates/values.yaml.tmpl) — Baseline values for the chart.
