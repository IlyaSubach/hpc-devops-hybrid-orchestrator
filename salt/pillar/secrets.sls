# Sensitive values kept out of states (assignment requirement: Salt Pillars
# for password + Munge key). This is a local, disposable lab environment;
# for anything real, encrypt this file (e.g. with salt GPG renderer / SOPS).
secrets:
  munge_key: 'S1STRJ8FpVI+gpxwRpafbizIBWnsZE3YStvG9qk2Rqnb6lDTh0yKHFrGoPAOVTIL'
  mariadb:
    slurm_password: 'Gz79jjeeswFtcX03fJbdidNx'
