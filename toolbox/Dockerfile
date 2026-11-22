# Toolbox image: everything needed to run this repo's Ansible + Terraform.
# Built by GitHub Actions, pulled and run by the self-hosted runner on vm-runner (VM 104).
FROM python:3.12-slim-bookworm

ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

# Base tools + Terraform from HashiCorp's apt repo
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-client git make jq curl gnupg ca-certificates \
 && curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com bookworm main" \
      > /etc/apt/sources.list.d/hashicorp.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends terraform \
 && rm -rf /var/lib/apt/lists/*

# Ansible + the collections the playbook uses
# (ansible.posix.sysctl; community.docker >= 3.8 for docker_container `pull: always`)
RUN pip install "ansible-core>=2.17,<3" \
 && ansible-galaxy collection install ansible.posix "community.docker:>=3.8.0" -p "$ANSIBLE_COLLECTIONS_PATH"

WORKDIR /work
CMD ["bash"]
