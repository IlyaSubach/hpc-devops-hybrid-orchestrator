# Container engine used by the Builder (image builds/exports) and the
# Controller (node exporter container).

podman:
  pkg.installed:
    - name: podman
