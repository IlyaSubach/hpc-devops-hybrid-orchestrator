# Baseline for every node: shared packages and static name resolution for the
# cluster (Slurm and Munge want stable hostnames).

common-packages:
  pkg.installed:
    - pkgs:
      - curl
      - ca-certificates

{% for name, node in pillar['cluster']['nodes'].items() %}
hosts-entry-{{ name }}:
  host.present:
    - ip: {{ node.ip }}
    - names:
      - {{ name }}
{% endfor %}
