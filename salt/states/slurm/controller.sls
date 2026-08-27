# Controller role: slurmdbd (accounting) + slurmctld (control daemon).

{% set slurm = pillar['slurm'] %}
{% set db_password = salt['pillar.get']('secrets:mariadb:slurm_password') %}

include:
  - munge
  - mariadb
  - slurm.common

slurmdbd-conf:
  file.managed:
    - name: /etc/slurm/slurmdbd.conf
    - source: salt://slurm/files/slurmdbd.conf.jinja
    - template: jinja
    - user: slurm
    - group: slurm
    - mode: '0600'
    - require:
      - cmd: slurm-debs-install

slurmctld-state-dir:
  file.directory:
    - name: /var/spool/slurmctld
    - user: slurm
    - group: slurm
    - mode: '0755'
    - require:
      - cmd: slurm-debs-install

slurmdbd-service:
  service.running:
    - name: slurmdbd
    - enable: True
    - require:
      - service: munge-service
      - cmd: slurm-db-user
    - watch:
      - file: slurmdbd-conf
      - file: munge-key

# Ensure the cluster exists in the accounting database before slurmctld starts.
register-cluster:
  cmd.run:
    - name: sacctmgr -i add cluster {{ slurm.cluster_name }}
    - unless: sacctmgr -n show cluster format=cluster%30 | grep -qw {{ slurm.cluster_name }}
    - retry:
        attempts: 5
        interval: 5
    - require:
      - service: slurmdbd-service

slurmctld-service:
  service.running:
    - name: slurmctld
    - enable: True
    - require:
      - file: slurmctld-state-dir
      - cmd: register-cluster
    - watch:
      - file: slurm-conf
      - file: munge-key
