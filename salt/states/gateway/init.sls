# Deploys the custom Slurm metrics gateway (built by the Builder node in
# Phase 1) onto K3s with its Helm chart.

{% set gateway = pillar['gateway'] %}
{% set monitoring = pillar['monitoring'] %}

include:
  - k3s
  - monitoring

gateway-image-import:
  cmd.run:
    - name: k3s ctr images import /vagrant/artifacts/images/slurm-metrics-gateway.tar
    - unless: k3s ctr images ls -q | grep -F '{{ gateway.image }}:{{ gateway.tag }}'
    - require:
      - service: k3s-service

# The fingerprint covers the chart files and the pillar-driven --set values,
# so the release re-deploys when either changes, retries after a failed
# install (no marker gets written), and is a no-op otherwise.
{% set gateway_fingerprint = "(cd /vagrant/helm/slurm-metrics-gateway && find . -type f -exec sha256sum {} + | sort; echo 'cfg " ~ gateway.image ~ ":" ~ gateway.tag ~ " " ~ gateway.port ~ " " ~ gateway.node_port ~ "')" %}

gateway-release:
  cmd.run:
    - name: >-
        helm upgrade --install slurm-metrics-gateway
        /vagrant/helm/slurm-metrics-gateway
        --namespace {{ monitoring.namespace }}
        --set image.repository={{ gateway.image }}
        --set image.tag={{ gateway.tag }}
        --set service.port={{ gateway.port }}
        --set service.nodePort={{ gateway.node_port }}
        --wait --timeout 5m0s
        && {{ gateway_fingerprint }} > /srv/monitoring/.gateway-release.applied
    - unless: >-
        helm status slurm-metrics-gateway -n {{ monitoring.namespace }} --output json
        | grep -q '"status":"deployed"'
        && {{ gateway_fingerprint }} | cmp -s - /srv/monitoring/.gateway-release.applied
    - env:
      - KUBECONFIG: /etc/rancher/k3s/k3s.yaml
    - require:
      - cmd: gateway-image-import
      - cmd: kps-release
