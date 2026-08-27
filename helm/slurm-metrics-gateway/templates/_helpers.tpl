{{- define "slurm-metrics-gateway.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "slurm-metrics-gateway.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "slurm-metrics-gateway.labels" -}}
app.kubernetes.io/name: {{ include "slurm-metrics-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "slurm-metrics-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "slurm-metrics-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
