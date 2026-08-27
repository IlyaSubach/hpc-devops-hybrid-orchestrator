# Shared between controller and compute: installs the role-appropriate subset
# of the Builder-produced DEBs and renders the cluster-wide slurm.conf.

{% set role_packages = {
    'controller': ['slurm-smd', 'slurm-smd-client', 'slurm-smd-slurmctld', 'slurm-smd-slurmdbd'],
    'compute':    ['slurm-smd', 'slurm-smd-client', 'slurm-smd-slurmd'],
} %}
{% set packages = role_packages[grains['id']] %}

include:
  - munge

# Create the slurm user with a pinned uid/gid BEFORE the DEBs install:
# the package postinst only creates the user if it does not exist, and a
# postinst-allocated uid would differ between controller and compute,
# breaking munge-authenticated RPCs between slurmctld and slurmd.
slurm-group:
  group.present:
    - name: slurm
    - gid: {{ pillar['slurm']['user']['gid'] }}
    - system: True

slurm-user:
  user.present:
    - name: slurm
    - uid: {{ pillar['slurm']['user']['uid'] }}
    - gid: {{ pillar['slurm']['user']['gid'] }}
    - system: True
    - shell: /usr/sbin/nologin
    - home: /var/lib/slurm
    - require:
      - group: slurm-group

# apt resolves runtime dependencies of the local DEBs from the Ubuntu archive.
slurm-debs-install:
  cmd.run:
    - name: >-
        apt-get -y install
        {%- for package in packages %}
        /vagrant/artifacts/debs/{{ package }}_*.deb
        {%- endfor %}
    - unless: dpkg-query -W {{ packages | join(' ') }}
    - env:
      - DEBIAN_FRONTEND: noninteractive
    - require:
      - user: slurm-user

slurm-log-dir:
  file.directory:
    - name: /var/log/slurm
    - user: slurm
    - group: slurm
    - mode: '0755'
    - require:
      - cmd: slurm-debs-install

slurm-conf:
  file.managed:
    - name: /etc/slurm/slurm.conf
    - source: salt://slurm/files/slurm.conf.jinja
    - template: jinja
    - makedirs: True
    - require:
      - cmd: slurm-debs-install
