# Kubernetes (k3s) on the homelab

Workflow: **Actions → homelab-kubernetes → Run workflow → `install` / `status` / `restart` / `redeploy`**
Playbook: `ansible/playbook/kubernetes.yml`, role: `ansible/roles/k3s/`

| Dropdown | Choices | Default |
|---|---|---|
| `action` | `install`, `status`, `restart`, `redeploy` | `install` |
| `controller` | `k8s-cp` | `k8s-cp` |
| `workers` (install, status) | `k8s-w2`, `k8s-w1`, `all` | `k8s-w2` |
| `target` (restart, redeploy) | `k8s-w2`, `k8s-w1`, `all-workers`, `k8s-cp`, `all` | `k8s-w2` |
| `confirm` (restart, redeploy) | type `restart` or `redeploy`, matching the action | empty |

`install` sets up the controller (if needed) and the selected workers. It never removes a worker
that you did not select. `status` checks that the controller and the selected workers are `Ready`,
and fails if any node is `NotReady`.

k3s = Kubernetes as one small binary (about half the memory of kubeadm), which suits the 3-3.5 GB VMs.
It ships with containerd, flannel networking, CoreDNS, Traefik (ingress), and metrics-server.

## Roadmap

| Step | What |
|---|---|
| 1 | Install k3s: server on **k8s-cp (100)**, agent on **k8s-w2 (102)** |
| 2 | Use the cluster from your Mac with `kubectl` |
| 3 | Deploy the auth service to the cluster (manifests) |
| 4 | Switch traffic, then remove the Docker containers from **k8s-w1** |
| 5 | Run `install` with workers = `k8s-w1` (or `all`): k8s-w1 joins |

k8s-w1 is left out at first because it runs the auth containers in Docker, and Docker's firewall
rules can break pod networking. Move the services off it before joining it. `install` stops for a
worker that has not joined yet and is running Docker containers (stopped containers are not detected).

## Restart and redeploy
Both only run when `confirm` is exactly the chosen action (lowercase, no spaces). Otherwise the run
fails before any VM is contacted. `install` and `status` ignore the field.

With `all-workers` and `all`, workers that never joined are skipped. Workers are handled one at a
time, and a failure stops the run.

- **restart** restarts the k3s service, not the VM, control plane first.
- **redeploy a worker** drains it, uninstalls k3s, removes its old node entry and joins it again.
  Data stored on that node by k3s (including `local-path` volumes) is **lost**. If the drain fails,
  k3s is not removed. The pinned `k3s_version` must match the control plane. It is not an upgrade.
- **redeploy `all`** uninstalls the workers and the control plane and installs an **empty cluster**:
  apps, secrets, volumes and cluster settings are **gone**, and old kubeconfig copies stop working.
  Back up first. `k8s-cp` cannot be redeployed alone.
- Redeploy stops before removing anything if a targeted worker runs Docker containers or cannot be
  reached. The k3s download happens after the uninstall; if a run fails part way, fix the cause and
  run it again (name the worker as `target` if it was already uninstalled) or use `install`.
- The `workers` dropdown is ignored by restart and redeploy. The final check covers the control plane
  and the included workers, and fails if any node is `NotReady`.

## Errors when something is not running
Failures start with `ERROR:` and name the VM: it cannot be reached over SSH, k3s is not installed,
the service is not running, or a node is not Ready. Search the failed workflow step for `ERROR:`.
A stopped service does not block `restart` or `install`, which can start it.

## Step 1: install
1. Make sure VMs 100 and 102 are running and `ssh ubuntu@192.168.8.100` works from vm-runner.
2. Run **homelab-kubernetes → install** with the default controller and workers. It installs the server, waits until it is Ready, reads the
   join token (never printed), installs the agent, then shows the nodes and system pods.
3. Run **status** any time to see them again. Expect `k8s-cp` and `k8s-w2` both `Ready`.

Re-running `install` is safe: finished steps are skipped.

## Step 2: kubectl from your Mac
```bash
brew install kubectl
```
```bash
mkdir -p ~/.kube && ssh ubuntu@192.168.8.100 'sudo cat /etc/rancher/k3s/k3s.yaml' | sed 's#127.0.0.1#192.168.8.100#' > ~/.kube/homelab.yaml && chmod 600 ~/.kube/homelab.yaml
```
```bash
export KUBECONFIG=~/.kube/homelab.yaml && kubectl get nodes -o wide
```
The kubeconfig is admin access to the cluster: keep it private, never commit it. Away from
home, `192.168.8.100` is reachable only through Tailscale with the subnet route.

Try: `kubectl get pods -A`, `kubectl top nodes`, `kubectl create deployment hello --image=nginx`.
Remove the test with `kubectl delete deployment hello`.

## Notes
- Version: pinned with `k3s_version` in `roles/k3s/defaults/main.yml` (it takes precedence over
  `k3s_channel`). Changing it does not upgrade nodes that are already installed.
- The built-in ingress (Traefik) uses ports 80 and 443 on the nodes. Add `--disable traefik` through
  `k3s_server_extra_args` if you prefer another one.
- Uninstall (by hand): `sudo /usr/local/bin/k3s-uninstall.sh` on the server,
  `sudo /usr/local/bin/k3s-agent-uninstall.sh` on an agent.
- The control plane (3 GB) is not tainted to stay free of workloads by default. Fine for a homelab.
