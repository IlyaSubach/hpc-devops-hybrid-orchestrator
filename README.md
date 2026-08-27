# The HPC-DevOps Hybrid Orchestrator

A reproducible, one-button lab that bridges a classic HPC scheduler (Slurm)
with a cloud-native observability stack (K3s + Prometheus + Grafana), built
with Vagrant + SaltStack.

```
                     vagrant up
                         |
   +---------------------+----------------------+
   |                     |                      |
+--v-------+      +------v------+      +--------v-------+
| builder  |      | controller  |      |    compute     |
| (ephem.) |      | salt master |      |  salt minion   |
|          |      | slurmctld   |      |  slurmd        |
| builds   | debs | slurmdbd    | jobs |  K3s:          |
| Slurm    +----->| MariaDB     +----->|   Prometheus   |
| DEBs +   | imgs | Podman:     |      |   Grafana      |
| images   |      |  node_exp.  |<-----+   gateway      |
| then     |      +-------------+scrape|   traefik      |
| poweroff |                           +----------------+
+----------+
192.168.56.10       192.168.56.11        192.168.56.12
```

The **builder** compiles the latest Slurm release into separated DEB packages
and builds/exports the container images, drops everything into the shared
`artifacts/` folder, then powers itself off. The **controller** (Salt master)
runs the Slurm control plane, accounting database, and a Podman-managed node
exporter. The **compute** node runs `slurmd` plus a single-node K3s cluster
hosting kube-prometheus-stack and the custom Slurm metrics gateway.

Every 5 minutes a cron job on the controller submits a Slurm batch job; the
job (executing on the compute node) simulates CPU/GPU/memory load and pushes
it to the metrics gateway, where Prometheus scrapes it and Grafana renders it
on the **Live Slurm Job Load** dashboard.

## Prerequisites

- [VirtualBox](https://www.virtualbox.org/) 7.x
- [Vagrant](https://developer.hashicorp.com/vagrant/downloads) 2.4.9+
  (needed for VirtualBox 7.2 support)
- ~12 GB free RAM at peak, ~40 GB free disk, and internet access
  (source tarballs, apt, Helm charts, container images)

## Quick start

```bash
vagrant up
```

That single command:

1. Boots **builder**, which compiles Slurm DEBs from source (~10-20 min),
   builds the gateway container image, exports both to `artifacts/`, and
   powers off.
2. Boots **controller**, installs the Salt master (key auto-accept enabled)
   and applies its highstate: Podman, node exporter container, MariaDB,
   Munge, slurmdbd, slurmctld, and the metrics cron job.
3. Boots **compute**, whose minion registers with the master and applies its
   highstate: Munge, slurmd, K3s, kube-prometheus-stack (Helm), and the
   metrics gateway (custom Helm chart).

Expect the full bring-up to take 30-45 minutes depending on hardware and
network speed.

## Accessing Grafana

1. Add the ingress hostname to your **host** machine's hosts file
   (as Administrator on Windows):

   ```powershell
   Add-Content C:\Windows\System32\drivers\etc\hosts "192.168.56.12 grafana.local"
   ```

   On Linux/macOS: `echo "192.168.56.12 grafana.local" | sudo tee -a /etc/hosts`

2. Browse to **https://grafana.local** (accept the self-signed certificate
   warning - the ingress uses Traefik's default cert).

3. Log in with `admin` / `admin`.

4. Dashboards:
   - **Node Exporter Full** (ID 1860) - host metrics for both VMs, scraped
     from the Podman node exporter on the controller and the node exporter
     on the compute node.
   - **Live Slurm Job Load** - the custom panel fed by Slurm jobs through
     the metrics gateway. Give the cron job up to 5 minutes to fire, then
     filter by Slurm Job ID / node.

## Verifying the pipeline

```bash
# Slurm cluster healthy?
vagrant ssh controller -c "sinfo && squeue"

# Fire a metrics job right now instead of waiting for cron:
vagrant ssh controller -c "sbatch /opt/slurm-jobs/metrics-sim.sbatch && squeue"

# Gateway exposing what the job pushed?
vagrant ssh controller -c "curl -s http://192.168.56.12:30080/metrics | grep slurm_job"

# Kubernetes side:
vagrant ssh compute -c "kubectl get pods -n monitoring"
```

## Repository layout

```
Vagrantfile                  # 3 nodes; reads topology from salt/pillar/cluster.yaml
salt/
  configs/master.conf        # Salt master: auto-accept + shared-folder roots
  pillar/
    cluster.yaml             # SINGLE SOURCE OF TRUTH: IPs, sizing, box
    cluster.sls              # derived pillar: slurm/gateway/monitoring config
    secrets.sls              # munge key + DB password (pillar-only secrets)
  states/
    top.sls                  # role -> state mapping (matched on minion id)
    common/                  # base packages + /etc/hosts wiring
    podman/                  # container engine (builder + controller)
    builder/                 # Slurm DEB compilation + image export
    node_exporter/           # podman container under systemd (controller)
    munge/                   # shared-key auth for Slurm
    mariadb/                 # slurmdbd backing store (pillar credentials)
    slurm/                   # common config, controller, compute, cron roles
    k3s/                     # single-node Kubernetes on compute
    monitoring/              # kube-prometheus-stack via Helm
    gateway/                 # image import + custom Helm chart deploy
gateway/                     # Python metrics gateway + Containerfile
helm/slurm-metrics-gateway/  # Helm chart (Deployment, Service, ServiceMonitor,
                             # Grafana dashboard ConfigMap)
```

## Design decisions

- **One source of truth for topology.** `salt/pillar/cluster.yaml` is read by
  the Vagrantfile (Ruby YAML) *and* imported into pillar (`import_yaml`), so
  IPs and sizing exist in exactly one place. The compute minion's master
  address is generated into `.vagrant/salt-configs/` at `vagrant` parse time.
- **The builder is also Salt-managed.** It runs masterless (`salt-call
  --local`) against the same state tree, so e.g. the `podman` state is shared
  with the controller instead of duplicated in shell scripts.
- **Idempotency.** Artifact builds are guarded by marker files (`creates:`),
  container/image operations by `unless:` checks, and the node exporter runs
  under systemd with `--rm` + pre-start cleanup (re-running the highstate
  never duplicates containers). The Helm releases are guarded by
  applied-fingerprint markers: a no-change highstate skips them, a values or
  chart change re-deploys them, and a previously failed install is retried.
- **Secrets live in pillar** (`secrets.sls`) and are only targeted at the
  nodes that need them — states reference `pillar.get`, never literals.
- **Scraping both node exporters** happens via `additionalScrapeConfigs`
  static targets on the private-network IPs, per the assignment; the gateway
  is scraped through a `ServiceMonitor` at a 5s interval to match the job's
  push cadence.
- **Gateway runs a single gunicorn worker** because the Prometheus registry
  is in-process state; multiple workers would answer `/metrics` with
  inconsistent snapshots.

## Troubleshooting

- **Provisioning was interrupted?** Re-run `vagrant provision <node>` — every
  state is idempotent, so it continues where it stopped.
- **Salt repo download errors** during the "Pre-installing Salt" step mean
  the retries (IPv4, 10 attempts per URL) were exhausted — check host
  connectivity, then re-run `vagrant provision <node>`. Salt is deliberately
  pre-installed this way because bootstrap-salt downloads the same files
  with no retries, which is unreliable behind VirtualBox NAT.
- **Builder artifacts missing?** `vagrant up builder` re-runs the build; it
  skips anything already present in `artifacts/`.
- **Grafana unreachable?** Check the hosts-file entry, then
  `vagrant ssh compute -c "kubectl get ingress -n monitoring"`.
- **Re-apply configuration** after editing states/pillars:
  `vagrant ssh controller -c "sudo salt '*' state.apply"`.
