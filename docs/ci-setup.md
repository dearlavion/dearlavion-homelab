# CI/CD: push to `dev` → Proxmox is updated

Workflow: `.github/workflows/homelab-deploy-infra.yml` (`homelab-deploy-infra`)

Triggers on push to `dev` **only when infra files change** (`ansible/roles/infra`,
`ansible/playbook/site.yml`, `ansible/inventory`, `terraform/`, `toolbox/`, `ci/`).

## Why a self-hosted runner (unlike dearlavion-projects)

`dearlavion-projects` runs Ansible on a **GitHub-hosted** runner and SSHes to
the VPS, which works because the VPS has a **public IP**. The Proxmox host is
on a **private LAN IP** behind your router, so GitHub's machines can't reach
it. A self-hosted runner on the Proxmox host connects **out** to GitHub and
picks up jobs. No port forwarding, nothing exposed to the internet.

```
git push origin dev
   │
   ├─ Job 1  build-toolbox   (GitHub-hosted, ubuntu-latest)
   │          toolbox/Dockerfile → ghcr.io/dearlavion/dearlavion-homelab-toolbox:<sha>
   │
   └─ Job 2  deploy          (self-hosted runner ON the Proxmox host, label "pve")
              podman pull ghcr.io/dearlavion/dearlavion-homelab-toolbox:<sha>
              podman run … bash ci/run.sh
                 ansible-playbook playbook/site.yml -e target=<target>
                   roles/infra: host.yml → template.yml → api_token.yml → vms.yml
                   (vms.yml = terraform plan → safety check → apply)
                 then: wait for SSH on every VM
```

Nothing but **podman** and the **runner** is installed on the Proxmox host;
Ansible and Terraform live in the image.

Persistent data on the host: `/var/lib/homelab-state/`
(`terraform.tfstate` + `pve-token.auto.tfvars`). **Back this folder up.**

---

## One-time setup on the Proxmox host (as root)

### 1. Podman + a dedicated runner user

```bash
apt update && apt install -y podman
useradd -m -s /bin/bash github-runner

# rootless podman needs sub-UID ranges (usually added automatically)
grep -q github-runner /etc/subuid || \
  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 github-runner

# keep the user's runtime dir alive without a login session
loginctl enable-linger github-runner
```

### 2. State folder + SSH key

```bash
mkdir -p /var/lib/homelab-state
chown github-runner: /var/lib/homelab-state
chmod 700 /var/lib/homelab-state

su - github-runner -c 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519'

# let the runner SSH to root@pve (Ansible needs root on the host)
cat /home/github-runner/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
```

This same key is put into every VM by Terraform, so the runner can also
reach the VMs.

### 3. Install the GitHub runner

On GitHub: **repo → Settings → Actions → Runners → New self-hosted runner →
Linux / x64**. Copy the *Download* commands and the *token* from that page.

```bash
su - github-runner
mkdir actions-runner && cd actions-runner
# paste the "curl -o actions-runner-linux-x64-…tar.gz" and "tar xzf" lines here

./config.sh --url https://github.com/dearlavion/dearlavion-homelab \
  --token <TOKEN_FROM_PAGE> --name pve --labels pve --unattended
exit
```

Back as root, install it as a service:

```bash
cd /home/github-runner/actions-runner
echo "XDG_RUNTIME_DIR=/run/user/$(id -u github-runner)" >> .env
./svc.sh install github-runner
./svc.sh start
./svc.sh status
```

The runner should now show **Idle** on the Runners page.

Quick test that rootless podman works for the runner:

```bash
su - github-runner -c 'podman run --rm docker.io/library/alpine echo ok'
```

---

## Repository variables

GitHub: **repo → Settings → Secrets and variables → Actions → Variables**
(or with `gh variable set NAME -b VALUE`):

| Variable | Example | Used for |
|---|---|---|
| `PVE_HOST` | `192.168.1.10` | Ansible → Proxmox host |
| `PVE_ENDPOINT` | `https://192.168.1.10:8006/` | Terraform API |
| `PVE_NODE` | `pve` | Node name (optional, default `pve`) |
| `NET_PREFIX` | `192.168.1` | VM IPs = prefix + VM ID |
| `GATEWAY` | `192.168.1.1` | VM gateway + DNS |
| `VM_EXTRA_SSH_KEY` | contents of your Mac's `~/.ssh/id_ed25519.pub` | So you can SSH to the VMs from your Mac |

No secrets are needed: the Proxmox API token is created by Ansible and kept
in `/var/lib/homelab-state` on the host.

---

## Using it

```bash
git checkout -b dev        # first time
git push -u origin dev     # every push to dev runs the pipeline
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

CI uses its own state on the host. Either delete VMs 100-103 first, or copy
your Mac's state over once:

```bash
scp terraform/terraform.tfstate root@192.168.1.10:/var/lib/homelab-state/
ssh root@192.168.1.10 chown github-runner: /var/lib/homelab-state/terraform.tfstate
```

### Security notes

- The workflow runs only on **push to `dev`** and **manual runs**, never on
  pull requests, so forks cannot run code on your server. Don't add a
  `pull_request` trigger to the `deploy` job.
- The runner's SSH key can log in to Proxmox as root. Protect the `dev`
  branch (Settings → Branches) so only you can push to it.
