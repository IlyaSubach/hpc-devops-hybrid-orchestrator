# MariaDB backing store for slurmdbd. Credentials come from pillar
# (assignment requirement).
#
# The database/user/grants are managed with the mysql CLI as root over the
# local unix socket (Ubuntu's default unix_socket auth) instead of Salt's
# mysql_* states: the onedir Salt minion bundles its own Python and cannot
# import apt's python3-pymysql, so the mysql modules would never load.

{% set db = pillar['slurm']['db'] %}
{% set db_password = salt['pillar.get']('secrets:mariadb:slurm_password') %}

mariadb-packages:
  pkg.installed:
    - pkgs:
      - mariadb-server

# InnoDB sizing recommended by the Slurm accounting docs.
mariadb-slurm-tuning:
  file.managed:
    - name: /etc/mysql/mariadb.conf.d/60-slurm.cnf
    - source: salt://mariadb/files/60-slurm.cnf
    - require:
      - pkg: mariadb-packages

mariadb-service:
  service.running:
    - name: mariadb
    - enable: True
    - require:
      - pkg: mariadb-packages
    - watch:
      - file: mariadb-slurm-tuning

slurm-database:
  cmd.run:
    - name: mysql -e "CREATE DATABASE IF NOT EXISTS {{ db.name }}"
    - unless: mysql -e "USE {{ db.name }}"
    - require:
      - service: mariadb-service

# The unless check proves the login works AND the grant is in place; if the
# pillar password ever changes, the check fails and ALTER USER re-syncs it.
slurm-db-user:
  cmd.run:
    - name: >-
        mysql -e "CREATE USER IF NOT EXISTS '{{ db.user }}'@'localhost';
        ALTER USER '{{ db.user }}'@'localhost' IDENTIFIED BY '{{ db_password }}';
        GRANT ALL PRIVILEGES ON {{ db.name }}.* TO '{{ db.user }}'@'localhost';
        FLUSH PRIVILEGES;"
    - unless: mysql -u {{ db.user }} -p'{{ db_password }}' -e "USE {{ db.name }}"
    - hide_output: True
    - require:
      - cmd: slurm-database
