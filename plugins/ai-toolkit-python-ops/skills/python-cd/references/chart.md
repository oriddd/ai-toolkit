# python-cd — the complete chart

Back to [`SKILL.md`](../SKILL.md). Every file of `helm-chart/`, verbatim; with `forwardedAllowIps` set it passes
`helm lint --strict` and `helm template` as written (`helm lint` does not enforce the `required` value; only
`helm template` fails without it). Replace `my-service` in `Chart.yaml`, `values.yaml` and the commands
(`my-service-worker`, `my_service.liveness`) with the project's names; change nothing else without a reason.

## `Chart.yaml`

```yaml
apiVersion: v2
name: my-service
description: my-service API, worker and database migrations
type: application
version: 0.1.0
appVersion: "0.1.0"
```

## `values.yaml`

```yaml
image:
  repository: my-service
  tag: ""
  pullPolicy: IfNotPresent
imagePullSecrets: []

serviceAccount:
  create: true
  name: ""

existingSecret: my-service-credentials
env:
  DB_URL: postgresql+asyncpg://app@postgres:5432/orders
  DB_POOL_SIZE: "10"
forwardedAllowIps: ""
otel:
  endpoint: ""

api:
  port: 8000
  replicas: 2
  terminationGracePeriodSeconds: 45
  preStopSleepSeconds: 5
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits: { memory: 512Mi }
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
  podDisruptionBudget:
    minAvailable: 1

worker:
  enabled: true
  replicas: 1
  drainSeconds: 20
  terminationGracePeriodSeconds: 40
  heartbeatMaxAgeSeconds: 60
  metricsPort: 9090
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits: { memory: 512Mi }

migrations:
  enabled: true
  activeDeadlineSeconds: 300
  backoffLimit: 1

metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
  podMonitor:
    enabled: true
    interval: 30s

networkPolicy:
  enabled: true
  ingressControllerNamespace: ingress-nginx
  monitoringNamespace: monitoring
```

## `templates/_helpers.tpl`

```yaml
{{- define "app.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "app.selector" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}{{ default (include "app.fullname" .) .Values.serviceAccount.name }}{{- else -}}{{ default "default" .Values.serviceAccount.name }}{{- end -}}
{{- end -}}

{{- define "app.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}

{{- define "app.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
fsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "app.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{- define "app.env" -}}
{{- range $name, $value := .root.Values.env }}
- name: {{ $name }}
  value: {{ $value | quote }}
{{- end }}
- name: OTEL_SERVICE_NAME
  value: {{ printf "%s-%s" (include "app.fullname" .root) .component | quote }}
{{- with .root.Values.otel.endpoint }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ . | quote }}
{{- end }}
- name: POD_NAME
  valueFrom: { fieldRef: { fieldPath: metadata.name } }
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.pod.name=$(POD_NAME),k8s.namespace.name={{ .root.Release.Namespace }},service.version={{ .root.Values.image.tag | default .root.Chart.AppVersion }}"
{{- end -}}
```

## `templates/deployment-api.yaml`

```yaml
{{- $sel := dict "root" . "component" "api" }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}-api
  labels:
    {{- include "app.labels" . | nindent 4 }}
    app.kubernetes.io/component: api
spec:
  {{- if not .Values.api.autoscaling.enabled }}
  replicas: {{ .Values.api.replicas }}
  {{- end }}
  selector:
    matchLabels: {{- include "app.selector" $sel | nindent 6 }}
  strategy:
    rollingUpdate: { maxUnavailable: 0, maxSurge: 1 }
  template:
    metadata:
      labels:
        {{- include "app.labels" . | nindent 8 }}
        app.kubernetes.io/component: {{ $sel.component }}
    spec:
      serviceAccountName: {{ include "app.serviceAccountName" . }}
      automountServiceAccountToken: false
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets: {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ .Values.api.terminationGracePeriodSeconds }}
      securityContext: {{- include "app.podSecurityContext" . | nindent 8 }}
      containers:
        - name: api
          image: {{ include "app.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext: {{- include "app.containerSecurityContext" . | nindent 12 }}
          ports:
            - name: http
              containerPort: {{ .Values.api.port }}
          env:
            {{- include "app.env" $sel | nindent 12 }}
            - name: FORWARDED_ALLOW_IPS
              value: {{ required "forwardedAllowIps: the ingress controller's pod CIDR, never *" .Values.forwardedAllowIps | quote }}
          envFrom:
            - secretRef:
                name: {{ .Values.existingSecret }}
          lifecycle:
            preStop:
              sleep:
                seconds: {{ .Values.api.preStopSleepSeconds }}
          startupProbe:
            httpGet: { path: /health/live, port: http }
            periodSeconds: 2
            failureThreshold: 30
          livenessProbe:
            httpGet: { path: /health/live, port: http }
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet: { path: /health/ready, port: http }
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          resources: {{- toYaml .Values.api.resources | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: { sizeLimit: 64Mi }
```

## `templates/deployment-worker.yaml`

```yaml
{{- if .Values.worker.enabled }}
{{- $sel := dict "root" . "component" "worker" }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}-worker
  labels:
    {{- include "app.labels" . | nindent 4 }}
    app.kubernetes.io/component: worker
spec:
  replicas: {{ .Values.worker.replicas }}
  selector:
    matchLabels: {{- include "app.selector" $sel | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "app.labels" . | nindent 8 }}
        app.kubernetes.io/component: {{ $sel.component }}
    spec:
      serviceAccountName: {{ include "app.serviceAccountName" . }}
      automountServiceAccountToken: false
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets: {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ .Values.worker.terminationGracePeriodSeconds }}
      securityContext: {{- include "app.podSecurityContext" . | nindent 8 }}
      containers:
        - name: worker
          image: {{ include "app.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: ["my-service-worker"]
          securityContext: {{- include "app.containerSecurityContext" . | nindent 12 }}
          env:
            {{- include "app.env" $sel | nindent 12 }}
            - name: DRAIN_SECONDS
              value: {{ .Values.worker.drainSeconds | quote }}
            - name: HEARTBEAT_DIR
              value: /tmp/heartbeat
            - name: HEARTBEAT_MAX_AGE_SECONDS
              value: {{ .Values.worker.heartbeatMaxAgeSeconds | quote }}
            - name: METRICS_PORT
              value: {{ .Values.worker.metricsPort | quote }}
          ports:
            - name: metrics
              containerPort: {{ .Values.worker.metricsPort }}
          envFrom:
            - secretRef:
                name: {{ .Values.existingSecret }}
          livenessProbe:
            exec:
              command: ["python", "-m", "my_service.liveness"]
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          resources: {{- toYaml .Values.worker.resources | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: { sizeLimit: 64Mi }
{{- end }}
```

## `templates/migration-job.yaml`

```yaml
{{- if .Values.migrations.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "app.fullname" . }}-migrate
  labels:
    {{- include "app.labels" . | nindent 4 }}
    app.kubernetes.io/component: migrate
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "0"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ .Values.migrations.backoffLimit }}
  activeDeadlineSeconds: {{ .Values.migrations.activeDeadlineSeconds }}
  template:
    metadata:
      labels:
        {{- include "app.labels" . | nindent 8 }}
        app.kubernetes.io/component: migrate
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets: {{- toYaml . | nindent 8 }}
      {{- end }}
      securityContext: {{- include "app.podSecurityContext" . | nindent 8 }}
      containers:
        - name: migrate
          image: {{ include "app.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: ["alembic", "upgrade", "head"]
          securityContext: {{- include "app.containerSecurityContext" . | nindent 12 }}
          env:
            {{- include "app.env" (dict "root" . "component" "migrate") | nindent 12 }}
          envFrom:
            - secretRef:
                name: {{ .Values.existingSecret }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: { sizeLimit: 64Mi }
{{- end }}
```

## `templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "app.fullname" . }}
  labels:
    {{- include "app.labels" . | nindent 4 }}
    app.kubernetes.io/component: api
spec:
  selector: {{- include "app.selector" (dict "root" . "component" "api") | nindent 4 }}
  ports:
    - name: http
      port: 80
      targetPort: http
```

## `templates/serviceaccount.yaml`

```yaml
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "app.serviceAccountName" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
automountServiceAccountToken: false
{{- end }}
```

## `templates/hpa.yaml`

```yaml
{{- if .Values.api.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "app.fullname" . }}-api
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "app.fullname" . }}-api
  minReplicas: {{ .Values.api.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.api.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.api.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
```

## `templates/pdb.yaml`

```yaml
{{- $min := ternary .Values.api.autoscaling.minReplicas .Values.api.replicas .Values.api.autoscaling.enabled }}
{{- if gt (int $min) 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "app.fullname" . }}-api
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  minAvailable: {{ .Values.api.podDisruptionBudget.minAvailable }}
  selector:
    matchLabels: {{- include "app.selector" (dict "root" . "component" "api") | nindent 6 }}
{{- end }}
```

## `templates/servicemonitor.yaml`

```yaml
{{- if .Values.metrics.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels: {{- include "app.selector" (dict "root" . "component" "api") | nindent 6 }}
  endpoints:
    - port: http
      path: /metrics/
      interval: {{ .Values.metrics.serviceMonitor.interval }}
{{- end }}
```

## `templates/podmonitor.yaml`

```yaml
{{- if and .Values.worker.enabled .Values.metrics.podMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ include "app.fullname" . }}-worker
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels: {{- include "app.selector" (dict "root" . "component" "worker") | nindent 6 }}
  podMetricsEndpoints:
    - port: metrics
      path: /metrics
      interval: {{ .Values.metrics.podMonitor.interval }}
{{- end }}
```

## `templates/networkpolicy.yaml`

```yaml
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "app.fullname" . }}-api
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels: {{- include "app.selector" (dict "root" . "component" "api") | nindent 6 }}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.networkPolicy.ingressControllerNamespace }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.networkPolicy.monitoringNamespace }}
        - podSelector: {}
      ports:
        - port: http
{{- end }}
```
