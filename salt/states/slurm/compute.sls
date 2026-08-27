# Compute role: slurmd execution daemon.

include:
  - munge
  - slurm.common

slurmd-spool-dir:
  file.directory:
    - name: /var/spool/slurmd
    - mode: '0755'
    - require:
      - cmd: slurm-debs-install

slurmd-service:
  service.running:
    - name: slurmd
    - enable: True
    - require:
      - file: slurmd-spool-dir
      - service: munge-service
    - watch:
      - file: slurm-conf
      - file: munge-key
