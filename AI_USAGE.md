# AI usage disclosure

Per the submission criteria, this documents where AI assistance was used,
what it produced, and why.

## How AI was used

I used an AI assistant (Claude) as a pair-programmer to scaffold this
repository: the Vagrantfile, the SaltStack state/pillar tree, the metrics
gateway service, the Helm chart, and the documentation. The generated code
was then put through an adversarial AI review (multiple independent review
passes over Vagrant, Salt, Slurm, Kubernetes/Helm, and the gateway code,
with each finding re-verified before acting on it), and the confirmed
defects were fixed. I reviewed the result and I am responsible for it.

## What it did and why (per component)

- **Vagrantfile + `cluster.yaml`**: I wanted one source of truth for node
  IPs/sizing shared between Vagrant (Ruby) and Salt (pillar). The solution
  loads a single YAML file from both sides and generates the minion configs
  at `vagrant` parse time, which removes duplicated IPs entirely. The
  controller applies its highstate through an explicit wait-for-key step
  because the salt provisioner's built-in `run_highstate` races minion key
  acceptance.
- **Salt states**: per-role states (builder / controller / compute) with
  pillar-driven values and idempotency guards (`creates:`, `unless:`,
  fingerprint markers for the Helm releases) so a re-run of the highstate is
  a no-op when nothing changed and a retry when something previously failed.
- **Slurm build pipeline**: the builder compiles the official Slurm tarball
  with its bundled `debian/` packaging (`mk-build-deps` + `debuild`), which
  is what produces the separated DEBs the assignment asks for. The `slurm`
  user is created with a pinned UID on both nodes before the DEBs install,
  because munge-authenticated RPCs compare numeric UIDs across nodes.
- **MariaDB**: managed via the mysql CLI over the unix socket rather than
  Salt's `mysql_*` states — the onedir Salt minion bundles its own Python
  and cannot import apt's PyMySQL, so those state modules cannot load.
- **Metrics gateway**: a small Flask + prometheus-client service. Prometheus
  requires a stable label set per metric name, so the gateway validates
  payloads and rejects label-set changes; it runs a single gunicorn worker
  because the metric registry is in-process state.
- **Helm chart**: Deployment/Service plus a ServiceMonitor (so the
  Prometheus operator discovers the gateway) and a Grafana-sidecar ConfigMap
  carrying the custom "Live Slurm Job Load" dashboard.

## Verification status

Beyond the static review, the environment was verified end to end on the
target machine (Windows 11 host, VirtualBox 7.2, Vagrant 2.4.9):

- A clean-room `vagrant up` — from no VMs and no `artifacts/` — completed
  with zero failed states (builder 12/0, controller 30/0, compute 22/0) and
  the builder powered itself off after exporting the Slurm 26.05 DEBs and
  container images.
- The full metrics loop was exercised live: a submitted Slurm job pushed
  CPU/GPU/memory values through the gateway, they appeared on the gateway's
  `/metrics`, all Prometheus scrape targets (both node exporters and the
  gateway ServiceMonitor) reported `up=1`, and both the "Node Exporter Full"
  (1860) and the custom "Live Slurm Job Load" dashboards were provisioned
  in Grafana behind `https://grafana.local`.
- Runtime failures found and fixed during bring-up (the salt-bootstrap's
  unretried downloads being unreliable behind VirtualBox NAT, and a Vagrant
  trigger/provisioning race) are reflected in the Vagrantfile and README.
