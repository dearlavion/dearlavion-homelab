#!/usr/bin/env bash
# Runs INSIDE the toolbox container on vm-runner (VM 104), started by the workflow.
#   /work   = repo checkout
#   /state  = persistent folder on vm-runner (Terraform state + API token)
#   /ssh-ro = the runner user's ~/.ssh (read-only)
set -euo pipefail

: "${PVE_HOST:?set repo variable PVE_HOST}"   # read by inventory/group_vars/proxmox.yml
TARGET="${TARGET:-infra}"

# Docker runs as real root: hand files back to the runner user on exit,
# otherwise the next actions/checkout cannot clean the workspace.
trap 'chown -R "${HOST_UID:-0}:${HOST_GID:-0}" /work /state 2>/dev/null || true' EXIT

# SSH key (copied so ssh can write known_hosts)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cp /ssh-ro/id_ed25519 /ssh-ro/id_ed25519.pub ~/.ssh/
chmod 600 ~/.ssh/id_ed25519

# All settings as one JSON blob (safe for values with spaces, like SSH keys)
EXTRA_VARS=$(jq -nc \
  --arg target "$TARGET" \
  --arg key "${VM_EXTRA_SSH_KEY:-}" \
  --argjson upgrade "${PVE_FULL_UPGRADE:-false}" \
  --argjson destroy "${ALLOW_DESTROY:-false}" \
  --arg vm "${VM_NAME:-all}" \
  --argjson rebuild "${VM_REBUILD:-false}" \
  '{
     target: $target,
     infra_tf_state_path: "/state/terraform.tfstate",
     infra_tf_token_file: "/state/pve-token.auto.tfvars",
     infra_full_upgrade: $upgrade,
     infra_allow_destroy: $destroy,
     infra_vm: $vm,
     infra_rebuild: $rebuild,
     infra_extra_ssh_key: $key
   }')

cd /work/ansible
ansible-playbook playbook/site.yml -e "$EXTRA_VARS"
