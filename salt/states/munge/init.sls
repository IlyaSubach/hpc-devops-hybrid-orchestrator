# Munge authentication with a shared key from pillar - the key must be
# byte-identical on every Slurm node.

munge-package:
  pkg.installed:
    - name: munge

munge-key:
  file.managed:
    - name: /etc/munge/munge.key
    - contents_pillar: secrets:munge_key
    - user: munge
    - group: munge
    - mode: '0400'
    - require:
      - pkg: munge-package

munge-service:
  service.running:
    - name: munge
    - enable: True
    - watch:
      - file: munge-key
