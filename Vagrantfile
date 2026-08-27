# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Three-node HPC/DevOps lab:
#   builder    - ephemeral build box: compiles Slurm DEBs + container images, then powers off
#   controller - Salt master, slurmctld, slurmdbd, MariaDB, Podman (node exporter)
#   compute    - Salt minion, slurmd, single-node K3s with kube-prometheus-stack
#
# Topology (IPs, sizing, box) lives in salt/pillar/cluster.yaml so Vagrant and
# Salt share one source of truth.

require "yaml"
require "fileutils"

PROJECT_ROOT = File.dirname(__FILE__)
cluster = YAML.load_file(File.join(PROJECT_ROOT, "salt", "pillar", "cluster.yaml"))["cluster"]
nodes = cluster["nodes"]

# Salt minion configs are generated from cluster.yaml at `vagrant` parse time
# so the master IP is never hand-duplicated.
salt_config_dir = File.join(PROJECT_ROOT, ".vagrant", "salt-configs")
FileUtils.mkdir_p(salt_config_dir)

minion_configs = {
  "builder" => <<~CONF,
    id: builder
    file_client: local
    file_roots:
      base:
        - /vagrant/salt/states
    pillar_roots:
      base:
        - /vagrant/salt/pillar
  CONF
  "controller" => <<~CONF,
    id: controller
    master: 127.0.0.1
  CONF
  "compute" => <<~CONF,
    id: compute
    master: #{nodes["controller"]["ip"]}
  CONF
}
minion_configs.each do |name, body|
  File.write(File.join(salt_config_dir, "#{name}-minion.conf"), body)
end

# Salt is pre-installed here from the official repo instead of relying on
# the provisioner's bootstrap-salt script: the bootstrap downloads its repo
# files with no retries, and outbound HTTPS through VirtualBox NAT is
# intermittently flaky (IPv6), which killed several first boots. curl -4
# plus aggressive retries makes this deterministic. The Vagrant salt
# provisioner then detects Salt is installed, skips its bootstrap, and
# still manages configs / runs the highstate.
def salt_preinstall(node_name, master: false)
  packages = master ? "salt-minion salt-master" : "salt-minion"
  dpkg_check = master ? "dpkg -s salt-minion >/dev/null 2>&1 && dpkg -s salt-master >/dev/null 2>&1" : "dpkg -s salt-minion >/dev/null 2>&1"
  master_config = master ? <<~MASTER : ""
    cp /vagrant/salt/configs/master.conf /etc/salt/master
    systemctl enable salt-master >/dev/null 2>&1 || true
    systemctl restart salt-master
  MASTER

  <<~SHELL
    set -e
    export DEBIAN_FRONTEND=noninteractive
    if ! ( #{dpkg_check} ); then
      echo "Pre-installing Salt from the official repository (IPv4, with retries)..."
      mkdir -p /etc/apt/keyrings
      curl -4 -fsSL -m 60 --retry 10 --retry-all-errors --retry-delay 5 \
        https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public \
        -o /etc/apt/keyrings/salt-archive-keyring.pgp
      curl -4 -fsSL -m 60 --retry 10 --retry-all-errors --retry-delay 5 \
        https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.sources \
        -o /etc/apt/sources.list.d/salt.sources
      apt-get update
      apt-get install -y #{packages}
    fi
    cp /vagrant/.vagrant/salt-configs/#{node_name}-minion.conf /etc/salt/minion
    #{master_config}
    systemctl enable salt-minion >/dev/null 2>&1 || true
    systemctl restart salt-minion
    echo "Salt pre-install complete."
  SHELL
end

Vagrant.configure("2") do |config|
  config.vm.box = cluster["box"]

  nodes.each_key do |name|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: nodes[name]["ip"]

      node.vm.provider "virtualbox" do |vb|
        vb.name = "#{cluster['name']}-#{name}"
        vb.cpus = nodes[name]["cpus"]
        vb.memory = nodes[name]["memory"]
        vb.linked_clone = true
      end

      node.vm.provision "shell", inline: salt_preinstall(name, master: name == "controller")

      case name
      when "builder"
        # Masterless salt-call: reuses the same states/pillar tree (e.g. the
        # podman state) without duplicating provisioning logic in shell.
        node.vm.provision :salt do |salt|
          salt.masterless = true
          salt.minion_config = ".vagrant/salt-configs/builder-minion.conf"
          salt.run_highstate = true
          salt.verbose = true
          salt.colorize = true
        end
        # Ephemeral build box: power off once artifacts are exported.
        # Fires after `vagrant up` (provisioning runs inside the :up action)
        # and also after a manual `vagrant provision builder`.
        node.trigger.after :up, :provision do |t|
          t.info = "Builder artifacts complete - powering the builder off"
          t.run_remote = {
            inline: "nohup sh -c 'sleep 5 && /sbin/shutdown -h now' >/dev/null 2>&1 &",
          }
        end
      when "controller"
        node.vm.provision :salt do |salt|
          salt.install_master = true
          salt.master_config = "salt/configs/master.conf"
          salt.minion_config = ".vagrant/salt-configs/controller-minion.conf"
          # Highstate is applied by the shell step below instead: the
          # provisioner's own `salt '*' state.highstate` races the minion key
          # acceptance and intermittently fails with "No minions matched".
          salt.run_highstate = false
          salt.verbose = true
          salt.colorize = true
        end
        node.vm.provision "shell", inline: <<~SHELL
          set -e
          echo "Waiting for the controller minion key to be accepted..."
          for i in $(seq 1 90); do
            if salt-key -l acc 2>/dev/null | grep -qx controller; then break; fi
            sleep 2
          done
          salt-key -l acc | grep -qx controller
          echo "Applying the controller highstate..."
          salt-call --retcode-passthrough state.highstate
        SHELL
      when "compute"
        node.vm.provision :salt do |salt|
          salt.minion_config = ".vagrant/salt-configs/compute-minion.conf"
          salt.run_highstate = true
          salt.verbose = true
          salt.colorize = true
        end
      end
    end
  end
end
