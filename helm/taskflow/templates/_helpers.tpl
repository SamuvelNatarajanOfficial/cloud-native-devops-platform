{{/*
Expand the name of the chart.
*/}}
{{- define "taskflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified chart-level name, e.g. "taskflow" or
"myrelease-taskflow". Used as the prefix for every component's resource
name below - callers should not use this directly.
*/}}
{{- define "taskflow.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart name and version, e.g. "taskflow-0.1.0" - used in the
helm.sh/chart label.
*/}}
{{- define "taskflow.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every resource this chart creates.
*/}}
{{- define "taskflow.labels" -}}
helm.sh/chart: {{ include "taskflow.chart" . }}
app.kubernetes.io/part-of: taskflow
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{/*
Selector labels for one component (api-gateway / task-service / postgres).
Call as: include "taskflow.selectorLabels" (dict "root" . "component" "api-gateway")
Kept minimal and stable on purpose - Kubernetes forbids mutating an
existing Deployment/StatefulSet's selector, so nothing here should ever
need to change after the first install.
*/}}
{{- define "taskflow.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/*
Full label set for one component's resources/pod template: common chart
labels + that component's selector labels.
Call as: include "taskflow.componentLabels" (dict "root" . "component" "api-gateway")
*/}}
{{- define "taskflow.componentLabels" -}}
{{ include "taskflow.labels" .root }}
{{ include "taskflow.selectorLabels" . }}
{{- end -}}

{{/*
Fully-qualified resource name for one component, e.g. "taskflow-api-gateway".
Call as: include "taskflow.componentFullname" (dict "root" . "component" "api-gateway")
*/}}
{{- define "taskflow.componentFullname" -}}
{{- printf "%s-%s" (include "taskflow.fullname" .root) .component -}}
{{- end -}}
