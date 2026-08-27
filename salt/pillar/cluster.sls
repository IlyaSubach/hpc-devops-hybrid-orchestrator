{% import_yaml 'cluster.yaml' as cfg %}
{% set nodes = cfg.cluster.nodes %}

cluster: {{ cfg.cluster | json }}

slurm:
  # 'latest' -> the builder resolves the newest release from download.schedmd.com.
  # Pin an explicit version (e.g. '25.05.3') for fully reproducible builds.
  version: latest
  cluster_name: {{ cfg.cluster.name }}
  # Fixed UID/GID: munge-authenticated RPCs carry the numeric uid, so
  # SlurmUser must resolve to the SAME uid on every node. Left to the DEB
  # postinst, each node would allocate the next free system uid.
  user:
    uid: 401
    gid: 401
  db:
    name: slurm_acct_db
    user: slurm
  compute:
    cpus: {{ nodes.compute.cpus }}
    real_memory: {{ nodes.compute.slurm_real_memory | default(4096) }}

gateway:
  image: localhost/slurm-metrics-gateway
  tag: '0.1.0'
  port: 8000
  node_port: 30080

monitoring:
  namespace: monitoring
  release: monitoring
  grafana:
    admin_user: admin
    admin_password: admin
    hostname: grafana.local
  node_exporter:
    image: quay.io/prometheus/node-exporter
    tag: v1.9.1
    port: 9100

metrics_job:
  duration_seconds: 60
  interval_seconds: 5
  cron_every_minutes: 5
