# Prometheus node exporter as a Podman container on the Controller only,
# supervised by systemd so it survives reboots and never duplicates
# (--rm + ExecStartPre cleanup make restarts idempotent).

{% set node_exporter = pillar['monitoring']['node_exporter'] %}

include:
  - podman

node-exporter-image:
  cmd.run:
    - name: podman load -i /vagrant/artifacts/images/node-exporter.tar
    - unless: podman image exists {{ node_exporter.image }}:{{ node_exporter.tag }}
    - require:
      - pkg: podman

node-exporter-unit:
  file.managed:
    - name: /etc/systemd/system/node_exporter.service
    - source: salt://node_exporter/files/node_exporter.service.jinja
    - template: jinja
    - context:
        image: {{ node_exporter.image }}
        tag: {{ node_exporter.tag }}
        port: {{ node_exporter.port }}

node-exporter-systemd-reload:
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: node-exporter-unit

node-exporter-service:
  service.running:
    - name: node_exporter
    - enable: True
    - require:
      - cmd: node-exporter-image
      - module: node-exporter-systemd-reload
    - watch:
      - file: node-exporter-unit
