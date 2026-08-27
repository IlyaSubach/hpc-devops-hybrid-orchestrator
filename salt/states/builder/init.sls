# Ephemeral build node: compiles Slurm into separated DEB packages and
# builds/exports the container images consumed by the other nodes.
# All outputs land in /vagrant/artifacts (the Vagrant shared folder), so they
# survive this box being powered off.

{% set slurm = pillar['slurm'] %}
{% set gateway = pillar['gateway'] %}
{% set node_exporter = pillar['monitoring']['node_exporter'] %}

include:
  - podman

builder-build-deps:
  pkg.installed:
    - pkgs:
      - build-essential
      - fakeroot
      - devscripts
      - equivs
      - bzip2

artifact-directories:
  file.directory:
    - names:
      - /vagrant/artifacts/debs
      - /vagrant/artifacts/images
    - makedirs: True

slurm-build-script:
  file.managed:
    - name: /usr/local/bin/build-slurm-debs.sh
    - source: salt://builder/files/build-slurm-debs.sh.jinja
    - template: jinja
    - mode: '0755'
    - context:
        slurm_version: {{ slurm.version }}

# Guarded by a marker file so re-provisioning the builder never rebuilds
# artifacts that already exist.
build-slurm-debs:
  cmd.run:
    - name: /usr/local/bin/build-slurm-debs.sh
    - creates: /vagrant/artifacts/debs/.build-complete
    - require:
      - pkg: builder-build-deps
      - file: slurm-build-script
      - file: artifact-directories

build-gateway-image:
  cmd.run:
    - name: >-
        podman build -t {{ gateway.image }}:{{ gateway.tag }} /vagrant/gateway
        && podman save -o /vagrant/artifacts/images/slurm-metrics-gateway.tar
        {{ gateway.image }}:{{ gateway.tag }}
    - creates: /vagrant/artifacts/images/slurm-metrics-gateway.tar
    - require:
      - pkg: podman
      - file: artifact-directories

export-node-exporter-image:
  cmd.run:
    - name: >-
        podman pull {{ node_exporter.image }}:{{ node_exporter.tag }}
        && podman save -o /vagrant/artifacts/images/node-exporter.tar
        {{ node_exporter.image }}:{{ node_exporter.tag }}
    - creates: /vagrant/artifacts/images/node-exporter.tar
    - require:
      - pkg: podman
      - file: artifact-directories
