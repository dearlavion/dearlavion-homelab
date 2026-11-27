#!/usr/bin/env bash
# Runs INSIDE the toolbox container on vm-runner (VM 104), started by the workflow.
#   /work   = repo checkout
#   /state  = persistent folder on vm-runner (Terraform state + API token)
#   /ssh-ro = the runner user's ~/.ssh (read-only)
set -euo pipefail

# Which playbook: infra (default) | services | frontend | kubernetes | tunnel. Set by the workflow.
PLAYBOOK="${PLAYBOOK:-infra}"
case "$PLAYBOOK" in infra|services|frontend|kubernetes|tunnel) ;; *) echo "Unknown PLAYBOOK '$PLAYBOOK'" >&2; exit 1 ;; esac
if [ "$PLAYBOOK" = infra ]; then
  : "${PVE_HOST:?set repo variable PVE_HOST}"   # read by inventory/group_vars/proxmox.yml
fi
TARGET="${TARGET:-infra}"       # infra playbook
SERVICE="${SERVICE:-}"          # services playbook
APP="${APP:-}"                  # frontend playbook
ACTION="${ACTION:-}"            # kubernetes and tunnel playbooks

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
  --arg service "$SERVICE" \
  --arg app "$APP" \
  --arg operation "$ACTION" \
  --arg key "${VM_EXTRA_SSH_KEY:-}" \
  --argjson upgrade "${PVE_FULL_UPGRADE:-false}" \
  --argjson destroy "${ALLOW_DESTROY:-false}" \
  --arg vm "${VM_NAME:-all}" \
  --argjson rebuild "${VM_REBUILD:-false}" \
  '{
     target: $target,
     service: $service,
     app: $app,
     operation: $operation,
     infra_tf_state_path: "/state/terraform.tfstate",
     infra_tf_token_file: "/state/pve-token.auto.tfvars",
     infra_full_upgrade: $upgrade,
     infra_allow_destroy: $destroy,
     infra_vm: $vm,
     infra_rebuild: $rebuild,
     infra_extra_ssh_key: $key
   }')

cd /work/ansible
ansible-playbook "playbook/${PLAYBOOK}.yml" -e "$EXTRA_VARS"
