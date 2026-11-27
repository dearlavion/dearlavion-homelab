# Kubernetes (k3s) on the homelab

Workflow: **Actions → homelab-kubernetes → Run workflow → `install` / `status`**
Playbook: `ansible/playbook/kubernetes.yml`, role: `ansible/roles/k3s/`

k3s = Kubernetes as one small binary (about half the memory of kubeadm), which suits the 3-3.5 GB VMs.
It ships with containerd, flannel networking, CoreDNS, Traefik (ingress), and metrics-server.

## Roadmap

| Step | What |
|---|---|
| 1 | Install k3s: server on **k8s-cp (100)**, agent on **k8s-w2 (102)** |
| 2 | Use the cluster from your Mac with `kubectl` |
| 3 | Deploy the auth service to the cluster (manifests) |
| 4 | Switch traffic, then remove the Docker containers from **k8s-w1** |
| 5 | Add 101 to `k3s_agent_vm_ids` and run `install` again: k8s-w1 joins |

k8s-w1 is left out at first because it runs the auth containers in Docker, and Docker's firewall
rules can break pod networking. Move the services off it before joining it.

## Step 1: install
1. Make sure VMs 100 and 102 are running and `ssh ubuntu@192.168.8.100` works from vm-runner.
2. Run **homelab-kubernetes → install**. It installs the server, waits until it is Ready, reads the
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
- Version: `k3s_channel: stable` (default). Pin with `k3s_version` in `roles/k3s/defaults/main.yml`.
- The built-in ingress (Traefik) uses ports 80 and 443 on the nodes. Add `--disable traefik` through
  `k3s_server_extra_args` if you prefer another one.
- Uninstall (by hand): `sudo /usr/local/bin/k3s-uninstall.sh` on the server,
  `sudo /usr/local/bin/k3s-agent-uninstall.sh` on an agent.
- The control plane (3 GB) is not tainted to stay free of workloads by default. Fine for a homelab.
