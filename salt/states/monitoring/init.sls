# kube-prometheus-stack (Prometheus operator + Grafana) on the compute node's
# K3s cluster, deployed via Helm.

{% set monitoring = pillar['monitoring'] %}

include:
  - k3s

helm-binary:
  cmd.run:
    - name: curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    - creates: /usr/local/bin/helm
    - require:
      - pkg: common-packages

prometheus-helm-repo:
  cmd.run:
    - name: helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    - unless: helm repo list | grep -q prometheus-community
    - require:
      - cmd: helm-binary

kps-values:
  file.managed:
    - name: /srv/monitoring/kps-values.yaml
    - source: salt://monitoring/files/kps-values.yaml.jinja
    - template: jinja
    - makedirs: True

# Skipped only when the release is healthy AND the applied-values marker
# matches the current values file. A failed/interrupted install leaves no
# marker, so the next highstate retries it; a values change invalidates the
# marker, so it re-deploys. A no-change highstate never touches the release.
kps-release:
  cmd.run:
    - name: >-
        helm repo update prometheus-community
        && helm upgrade --install {{ monitoring.release }}
        prometheus-community/kube-prometheus-stack
        --namespace {{ monitoring.namespace }} --create-namespace
        -f /srv/monitoring/kps-values.yaml
        --wait --timeout 20m0s
        && cp /srv/monitoring/kps-values.yaml /srv/monitoring/.kps-values.applied
    - unless: >-
        helm status {{ monitoring.release }} -n {{ monitoring.namespace }} --output json
        | grep -q '"status":"deployed"'
        && cmp -s /srv/monitoring/kps-values.yaml /srv/monitoring/.kps-values.applied
    - env:
      - KUBECONFIG: /etc/rancher/k3s/k3s.yaml
    - require:
      - file: kps-values
      - service: k3s-service
      - cmd: prometheus-helm-repo
