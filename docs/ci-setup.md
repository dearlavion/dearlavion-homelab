# CI/CD: push to `dev` → Proxmox is updated

Workflows in `.github/workflows/` (all manual: **Actions → pick one → Run workflow**):

| File | Deploys | Dropdown |
|---|---|---|
| `homelab-deploy-infra.yml` | Proxmox host, template, VMs. **Also builds the toolbox image.** | `target` (toolbox, infra, infra-vms:<vm>, rebuild:<vm>, ...) |
| `homelab-services.yml` | Backend services (Docker on a VM) | `service` (auth-service) |
| `homelab-frontend.yml` | UIs (Docker, nginx + SPA) | `app` (security-ui) |
| `homelab-cloudflare-tunnel.yml` | DNS + HTTPS for the UIs (Cloudflare Tunnel, see `docs/tunnel.md`) | `action` (apply, status) |
| `homelab-kubernetes.yml` | k3s cluster (see `docs/kubernetes.md`) | `action` (install, status) |

**Toolbox image** (Ansible + Terraform): owned by `homelab-deploy-infra`, tagged by a hash of
`toolbox/`. Any infra choice builds it automatically **only if that tag is not in GHCR yet**
(first run, or after `toolbox/` changed). Target `toolbox` forces a rebuild and deploys nothing.
`homelab-services` does the same check and builds the image too if it is missing, so it works even
if infra was never run. (`homelab-frontend` has the same job.)

All workflows share one `concurrency` group (`homelab-deploy`), so only one runs at a time.
To add a service: add a role under `ansible/roles/`, a play in `playbook/services.yml`,
an option in `homelab-services.yml`, and any new secrets to that file. UIs: same with
`playbook/frontend.yml` and `homelab-frontend.yml` (see `docs/security-ui.md`).

| Machine | IP | Role |
|---|---|---|
| Proxmox host `pve` | 192.168.8.50 | Managed by the pipeline (Ansible + Terraform API) |
| **vm-runner (VM 104)** | 192.168.8.104 | Runs the GitHub runner; created **by hand**, not in Terraform |
| Router | 192.168.8.1 | Gateway + DNS |

## Why a self-hosted runner (unlike dearlavion-projects)

`dearlavion-projects` runs Ansible on a **GitHub-hosted** runner and SSHes to
the VPS, which works because the VPS has a **public IP**. Proxmox is on a
**private LAN IP** behind your router, so GitHub's machines can't reach it.
The runner on vm-runner connects **out** to GitHub (HTTPS, long polling) and
picks up jobs. No port forwarding, nothing exposed to the internet.

## Why VM 104 and not VM 103 or the Proxmox host

- **Not VM 103 (devops):** Terraform manages 100-103. A run that replaces 103
  would delete the runner in the middle of its own job.
- **Not the Proxmox host:** keeps podman and the runner off the hypervisor.

```
git push origin dev
   │
   ├─ Job 1  build-toolbox   (GitHub-hosted, ubuntu-latest)
   │          toolbox/Dockerfile → ghcr.io/dearlavion/dearlavion-homelab-toolbox:<sha>
   │
   └─ Job 2  deploy          (self-hosted runner on vm-runner, label "pve")
              podman pull ghcr.io/dearlavion/dearlavion-homelab-toolbox:<sha>
              podman run … bash ci/run.sh
                 ansible-playbook playbook/infra.yml -e target=<target>
                   roles/infra: host.yml → template.yml → api_token.yml → vms.yml
                   (vms.yml = terraform plan → safety check → apply)
                 then: wait for SSH on every VM
```

Persistent data on vm-runner: `/var/lib/homelab-state/`
(`terraform.tfstate` + `pve-token.auto.tfvars`). **Back up VM 104.**

---

## One-time setup

Prerequisite: VM 104 `vm-runner` exists (1 vCPU, 1 GB RAM, 15G on `local`,
IP 192.168.8.104) and you can `ssh ubuntu@192.168.8.104`.

All commands below run **on vm-runner** unless marked otherwise.

### 1. Swap file (1 GB RAM is tight while pulling images)

```bash
sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system >/dev/null
```

### 2. Podman + a dedicated runner user

```bash
sudo apt update && sudo apt install -y podman uidmap
sudo useradd -m -s /bin/bash github-runner

# rootless podman needs sub-UID ranges (usually added automatically)
grep -q github-runner /etc/subuid || \
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 github-runner

# keep the user's runtime dir alive without a login session
sudo loginctl enable-linger github-runner
```

### 3. State folder + SSH key

```bash
sudo mkdir -p /var/lib/homelab-state
sudo chown github-runner: /var/lib/homelab-state
sudo chmod 700 /var/lib/homelab-state

sudo -u github-runner mkdir -p -m 700 /home/github-runner/.ssh
sudo -u github-runner ssh-keygen -t ed25519 -N "" -f /home/github-runner/.ssh/id_ed25519
sudo cat /home/github-runner/.ssh/id_ed25519.pub     # copy this line
```

**On the Proxmox host** (`pve → Shell` in the web UI), allow that key to log
in as root (Ansible needs root on the host):

```bash
echo 'ssh-ed25519 AAAA...paste...the...line... github-runner@vm-runner' >> /root/.ssh/authorized_keys
```

Back **on vm-runner**, test it:

```bash
sudo -u github-runner ssh -o StrictHostKeyChecking=accept-new root@192.168.8.50 pveversion
```

This same key is also put into VMs 100-103 by Terraform, so the runner can
reach them too.

### 4. Install the GitHub runner

On GitHub: **repo → Settings → Actions → Runners → New self-hosted runner →
Linux / x64**. Copy the *Download* commands and the *token* from that page.

```bash
sudo -iu github-runner
mkdir actions-runner && cd actions-runner
# paste the "curl -o actions-runner-linux-x64-…tar.gz" and "tar xzf" lines here

./config.sh --url https://github.com/dearlavion/dearlavion-homelab \
  --token <TOKEN_FROM_PAGE> --name vm-runner --labels pve --unattended
echo "XDG_RUNTIME_DIR=/run/user/$(id -u)" >> .env
exit
```

Install it as a service:

```bash
cd /home/github-runner/actions-runner
sudo ./svc.sh install github-runner
sudo ./svc.sh start
sudo ./svc.sh status
```

The runner should now show **Idle** on the Runners page.

Quick test that rootless podman works for the runner:

```bash
sudo -iu github-runner podman run --rm docker.io/library/alpine echo ok
```

---

## Repository variables

GitHub: **repo → Settings → Secrets and variables → Actions → Variables**
(or with `gh variable set NAME -b VALUE`):

| Variable | Value | Used for |
|---|---|---|
| `PVE_HOST` | `192.168.8.50` | Ansible → Proxmox host |
| `PVE_ENDPOINT` | `https://192.168.8.50:8006/` | Terraform API |
| `PVE_NODE` | `pve` | Node name (optional, default `pve`) |
| `NET_PREFIX` | `192.168.8` | VM IPs = prefix + VM ID (.100-.103) |
| `GATEWAY` | `192.168.8.1` | VM gateway + DNS |
| `VM_EXTRA_SSH_KEY` | contents of your Mac's `~/.ssh/id_ed25519.pub` | So you can SSH to the VMs from your Mac |

```bash
gh variable set PVE_HOST     -b 192.168.8.50               -R dearlavion/dearlavion-homelab
gh variable set PVE_ENDPOINT -b https://192.168.8.50:8006/ -R dearlavion/dearlavion-homelab
gh variable set PVE_NODE     -b pve                        -R dearlavion/dearlavion-homelab
gh variable set NET_PREFIX   -b 192.168.8                  -R dearlavion/dearlavion-homelab
gh variable set GATEWAY      -b 192.168.8.1                -R dearlavion/dearlavion-homelab
gh variable set VM_EXTRA_SSH_KEY -b "$(cat ~/.ssh/id_ed25519.pub)" -R dearlavion/dearlavion-homelab
```

Infra needs no secrets: the Proxmox API token is created by the `infra` role
and kept in `/var/lib/homelab-state` on vm-runner. Deploying services does need
secrets; see [auth-service.md](auth-service.md).

---

## Using it

```bash
git checkout -b dev        # first time
git push -u origin dev     # every push to dev (touching infra files) runs the pipeline
```

Manual run with options: **Actions → homelab-deploy-infra → Run workflow**

| Option | Default | Effect |
|---|---|---|
| `target` | `infra` | `infra` = host + VMs, `infra-host` = host/template/token, `infra-vms` = VMs only |
| `allow_destroy` | off | Allow Terraform to delete or replace VMs |
| `full_upgrade` | off | Run `apt full-upgrade` on the Proxmox host |

### Safety: VM deletion is blocked by default

If a change would **delete or replace** a VM (e.g. you shrank a disk or
changed something that forces re-creation), the job stops before applying.
To allow it: run manually with `allow_destroy`, or include
`[allow-destroy]` in the commit message.

### Already ran Terraform from your Mac?

CI uses its own state on vm-runner. Either delete VMs 100-103 first, or copy
your Mac's state over once:

```bash
scp terraform/terraform.tfstate ubuntu@192.168.8.104:/tmp/
ssh ubuntu@192.168.8.104 'sudo mv /tmp/terraform.tfstate /var/lib/homelab-state/ && sudo chown github-runner: /var/lib/homelab-state/terraform.tfstate'
```

### Security notes

- The workflow runs only on **push to `dev`** and **manual runs**, never on
  pull requests, so forks cannot run code on your server. Don't add a
  `pull_request` trigger to the `deploy` job.
- The runner's SSH key can log in to Proxmox as root. Protect the `dev`
  branch (Settings → Branches) so only you can push to it.
- Turn on **Protection** for VM 104 in Proxmox (Options → Protection) so it
  can't be deleted by accident.
