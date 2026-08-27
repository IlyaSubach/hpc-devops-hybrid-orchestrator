# Phase 5 driver: a cron entry on the controller submits the metrics
# simulation batch job to Slurm every N minutes.

{% set job = pillar['metrics_job'] %}

metrics-job-batch-script:
  file.managed:
    - name: /opt/slurm-jobs/metrics-sim.sbatch
    - source: salt://slurm/files/metrics-sim.sbatch.jinja
    - template: jinja
    - makedirs: True
    - mode: '0755'

metrics-job-submit-script:
  file.managed:
    - name: /usr/local/bin/submit-metrics-job.sh
    - source: salt://slurm/files/submit-metrics-job.sh.jinja
    - template: jinja
    - mode: '0755'

# Submitted as the unprivileged vagrant user (same uid on all nodes).
metrics-job-cron:
  cron.present:
    - name: /usr/local/bin/submit-metrics-job.sh >> /home/vagrant/metrics-sim-cron.log 2>&1
    - identifier: slurm-metrics-sim
    - user: vagrant
    - minute: '*/{{ job.cron_every_minutes }}'
    - require:
      - file: metrics-job-submit-script
      - file: metrics-job-batch-script
