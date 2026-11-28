# Security UI → k8s-w1 (Docker)

Workflow: **Actions → homelab-frontend → Run workflow → app `security-ui`**
(or push to `dev` in `dearlavion-security-ui`, whose `homelab-dev.yml` triggers it).

```
UI repo push to dev ─► homelab-dev.yml: build image ghcr.io/dearlavion/dearlavion-security-ui:homelab
                          └─ gh workflow run homelab-frontend.yml (needs HOMELAB_DISPATCH_TOKEN)
homelab-frontend ─► vm-runner: docker run toolbox ─► ansible playbook/frontend.yml -e app=security-ui
   SSH ubuntu@<NET_PREFIX>.101 (k8s-w1): install Docker (if missing) → docker login ghcr.io
   → check the auth service answers /actuator/health = UP → render /etc/security-ui/nginx.conf
   → docker run security-ui  -p 8080:80  (nginx.conf mounted over the image's) → wait for HTTP 200
```

## How the browser reaches the API
The browser only talks to this container (same origin, which the refresh cookie needs).
nginx forwards `/api/v1/auth/` and `/api/v1/superadmin/` to the auth service. The image's own
`nginx.conf` hardcodes the host `auth`, so the role renders its own from
`roles/security_ui/templates/nginx.conf.j2` and mounts it. The upstream defaults to the auth
container on the same VM (`http://<VM IP>:9081`); change `security_ui_auth_upstream` if it moves.

## One-time setup
Needs `GHCR_TOKEN` (secret) and `GHCR_USER` (variable) in the homelab repo, the same ones
`auth-service` uses. In `dearlavion-security-ui`, add the secret `HOMELAB_DISPATCH_TOKEN`
(same token as in the auth repo).

The UI logs in to the `security` tenant (`X-Customer: security`), so the auth service must list
it in `CUSTOMERS`. `auth_service_customers` now includes it: **redeploy the auth service once**.
You also need a SUPERADMIN user in that tenant (see the auth service README).

## Open it
```
http://192.168.8.101:8080        # from the LAN (or via Tailscale with the subnet route)
```
Over plain HTTP the session cookie works because the auth service runs with
`SESSION_COOKIE_SECURE=false`. Behind HTTPS, set it to `true`.

```bash
ssh ubuntu@192.168.8.101 'sudo docker logs --tail 50 security-ui'
```
