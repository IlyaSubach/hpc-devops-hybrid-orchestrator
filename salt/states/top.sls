base:
  'builder':
    - common
    - podman
    - builder

  'controller':
    - common
    - podman
    - node_exporter
    - munge
    - mariadb
    - slurm.common
    - slurm.controller
    - slurm.cron

  'compute':
    - common
    - munge
    - slurm.common
    - slurm.compute
    - k3s
    - monitoring
    - gateway
