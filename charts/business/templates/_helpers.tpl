{{/* Standard labels applied to every resource we own. */}}
{{- define "business.labels" -}}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: business
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
env: production
{{- end -}}
