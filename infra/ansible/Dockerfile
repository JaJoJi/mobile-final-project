# Toolbox for infra/ansible: Azure CLI + Ansible in one pinned image.
# Ansible's controller doesn't run on native Windows, so every teammate
# (Windows, macOS, Linux) runs the playbooks through this container via
# ./run.sh -- same versions for everyone.
FROM mcr.microsoft.com/azure-cli:2.90.0@sha256:e3768dde8142efa45d8f356a317aaac77abd7da15ba3719b0a150e9453f251db

RUN tdnf install -y python3-pip openssh-clients \
 && tdnf clean all \
 && python3 -m pip install --no-cache-dir ansible-core==2.21.4

ENV ANSIBLE_CONFIG=/work/infra/ansible/ansible.cfg
WORKDIR /work/infra/ansible
ENTRYPOINT []
