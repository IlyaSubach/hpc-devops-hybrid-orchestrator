# Single-node K3s cluster on the compute node.

{% set compute_ip = pillar['cluster']['nodes']['compute']['ip'] %}

k3s-install:
  cmd.run:
    - name: >-
        curl -sfL https://get.k3s.io |
        sh -s - server
        --write-kubeconfig-mode 644
        --node-ip {{ compute_ip }}
    - creates: /usr/local/bin/k3s
    - require:
      - pkg: common-packages

k3s-service:
  service.running:
    - name: k3s
    - enable: True
    - require:
      - cmd: k3s-install
