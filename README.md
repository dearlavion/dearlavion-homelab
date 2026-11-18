# Homelab: Proxmox + 4 VMs as code

| Tool | Does | Replaces manual steps |
|---|---|---|
| **Ansible** `ansible/pve-host.yml` | Repos, upgrade, storage content, swappiness, cloud-init snippet, Ubuntu template 9000, Terraform API token | 2, 3, 4 |
| **Terraform** `terraform/` | Creates VMs 100-103 (CPU, RAM, disk, IP, boot order) and writes the Ansible inventory | 5, 6 |

| VM | Name | vCPU | RAM | Disk | IP |
|---|---|---|---|---|---|
| 100 | k8s-cp | 2 | 3 GB | 15G | .100 |
| 101 | k8s-w1 | 2 | 3.5 GB | 20G | .101 |
| 102 | k8s-w2 | 2 | 3.5 GB | 20G | .102 |
| 103 | devops | 1 | 1.5 GB | 10G | .103 |

All disks on `local-lvm`. `local` keeps only OS, snippets, backups.

## Still manual (one time)

- Install Proxmox.
- Storage resize you already did (swap 4G, `lvextend` of `pve/data`).

## Where to run this

From your **laptop/PC** (macOS, Linux, or Windows WSL) — called the *controller*.
Later you can move this repo onto VM 103 and run it from there.

## 1. Install tools on the controller

```bash
# macOS
brew install ansible terraform

# Ubuntu / WSL
sudo apt install -y ansible
# Terraform: https://developer.hashicorp.com/terraform/install
```

## 2. SSH key + access to Proxmox as root

```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519
ssh-copy-id root@192.168.1.10        # your Proxmox IP
ssh root@192.168.1.10 pveversion     # should work without password
```

## 3. Edit your values

- `ansible/inventory/pve.ini` → Proxmox IP
- `terraform/terraform.tfvars`:
  ```bash
  cp terraform/terraform.tfvars.example terraform/terraform.tfvars
  ```
  then set `pve_endpoint`, `pve_node`, `net_prefix`, `gateway`.

Check the node name with `hostname` on the Proxmox host (yours is `pve`).

## 4. Run

```bash
make host    # Ansible: prepare host + template + API token
make plan    # Terraform: preview
make vms     # Terraform: create the 4 VMs (type 'yes')
make ping    # Ansible: all 4 VMs should answer 'pong'
```

`make host` saves the API token to `terraform/pve-token.auto.tfvars`
(Terraform loads it automatically; it is git-ignored).

The first `make vms` takes a few minutes: Terraform waits until each VM's
guest agent is running (installed by cloud-init on first boot).

## Day-to-day

| Want to | Do |
|---|---|
| Change RAM/CPU/disk | Edit `locals` in `terraform/main.tf`, `make vms` |
| Rebuild everything | `make destroy` then `make vms` |
| Rebuild one VM | `cd terraform && terraform apply -replace='proxmox_virtual_environment_vm.vm["k8s-w1"]'` |
| Re-run host setup | `make host` (safe, idempotent) |
| Rebuild the template | `qm destroy 9000` on the host, then `make host` |

Disks can only **grow** in Terraform; shrinking a `disk` value fails.

## Notes

- The Terraform API user gets the `Administrator` role — fine for a homelab;
  tighten to a custom role later if you want least-privilege.
- Lost the token file? On the host: `pveum user token remove terraform@pve tf`, then `make host`.
- If you already created VMs 100-103 by hand, delete them first
  (`qm stop <id>; qm destroy <id> --purge`) or Terraform will fail with "VM already exists".
