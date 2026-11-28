# security.travelbesty.store on the internet (Cloudflare Tunnel)

Workflow: **Actions → homelab-cloudflare-tunnel → Run workflow → `apply` / `status`**
Playbook: `ansible/playbook/tunnel.yml`, role: `ansible/roles/cloudflared/`

```
Browser ──HTTPS──► Cloudflare (DNS + certificate + optional login)
                       │  tunnel: opened OUTWARD by the connector, so no router ports
                       ▼
        k8s-w1 (192.168.8.101): cloudflared container ─► security-ui :8080 (nginx) ─► auth-service :9081
```

Nothing is opened on your router. HTTPS is Cloudflare's certificate (automatic and free).
Docker only: no Kubernetes involved.

---

## Part 1: Cloudflare (once, in the browser)

### 1. Create an account
`https://dash.cloudflare.com/sign-up` → email + password, verify the email.

### 2. Add your domain
1. Dashboard → **Add a domain** (or **Onboard a domain**) → type `travelbesty.store` → continue.
2. Choose the **Free** plan.
3. Cloudflare scans the existing DNS records. Review them and keep what you need, then continue.
4. It shows **two nameservers**, like `xxxx.ns.cloudflare.com`. Keep this page open.

### 3. Point the domain at Cloudflare (at your registrar, where you bought it)
1. If **DNSSEC** is on at the registrar, turn it off first (it breaks the switch). You can re-enable it later from Cloudflare.
2. In the domain's **nameservers** setting, choose "custom nameservers" and replace the existing ones with the **two Cloudflare gave you**. Save.
3. Back in Cloudflare click **Check nameservers now**. It can take minutes up to a few hours. The domain
   shows **Active** (and you get an email) when it is done. Do not continue before that.

### 4. Force HTTPS
Domain → **SSL/TLS → Edge Certificates** → turn on **Always Use HTTPS**.
(The tunnel itself needs no certificate on your server. Cloudflare terminates HTTPS.)

### 5. Create the API token the pipeline uses
1. Top-right profile → **My Profile → API Tokens → Create Token → Create Custom Token**.
2. Name: `homelab-cloudflare-tunnel`.
3. Permissions (three rows):
   - **Account** · **Cloudflare Tunnel** · **Edit**
   - **Zone** · **DNS** · **Edit**
   - **Zone** · **Zone** · **Read**
4. Account Resources: **Include → your account**. Zone Resources: **Include → Specific zone → travelbesty.store**.
5. **Continue → Create Token** and **copy it now**: it is shown once.

---

## Part 2: GitHub (once)

Homelab repo → **Settings → Secrets and variables → Actions → Secrets → New repository secret**
- Name: `CLOUDFLARE_API_TOKEN` (exactly), Secret: the token from step 5.

The other secrets and variables (`GHCR_TOKEN`, `GHCR_USER`, `AUTH_*`, `NET_PREFIX`) are already in place from the auth deploys.

---

## Part 3: Deploy, in this order

Commit and push the homelab changes to `dev` first. Then run, one after the other:

1. **homelab-services → `auth-service`**: switches the session cookie to HTTPS-only (`SESSION_COOKIE_SECURE=true`),
   adds the UI's `https://` origin, and keeps the `security` tenant.
2. **homelab-frontend → `security-ui`**: installs the hardened nginx config (see below).
3. **homelab-cloudflare-tunnel → `apply`**: creates the tunnel `homelab`, its route
   `security.travelbesty.store → http://192.168.8.101:8080`, the DNS record (CNAME, proxied), starts the
   `cloudflared` container on k8s-w1, then checks the tunnel is healthy and the public URL answers.

First run of any workflow also builds the toolbox image (a new collection was added), which takes a few minutes.

Open **https://security.travelbesty.store**. Run **homelab-cloudflare-tunnel → `status`** any time to re-check.

---

## Part 4: Lock it down (do this before sharing the URL)

This is a **superadmin** UI on the open internet.

1. **Put a login in front (Cloudflare Access, free for small teams).**
   1. `https://one.dash.cloudflare.com` → first time: pick a team name and the **Free** plan (it may ask for a payment method; the plan costs $0).
   2. **Access → Applications → Add an application → Self-hosted**.
   3. Name `security-ui`, Domain `security.travelbesty.store`.
   4. Add a policy: **Action: Allow**, **Include → Emails → your email**. Login method **One-time PIN** (default).
   5. Save. Visitors now must enter an emailed code before the page even loads.
2. **Change the Mongo password.** The `admin` user's password was pasted in chat. Atlas → Database Access → edit → new strong password → update the `AUTH_MONGODB_URI` secret → redeploy the auth service.
3. **Use a strong `AUTH_JWT_SECRET`** (not the default in the public source) and set `AUTH_PROVISION_SECRET`.
4. **Create the first SUPERADMIN** in the `security` tenant (see the auth service README), or you cannot log in.

What the pipeline already does for you:
- nginx exposes only `session/login`, `session/refresh`, `session/logout` of the auth API. Register,
  password reset and the rest return 404 from outside.
- Login attempts are rate limited per visitor (about 10 per minute).
- The refresh cookie is `Secure`, `HttpOnly`, `SameSite=Strict`.

---

## Adding another UI later
Add a line to `cloudflared_routes` in `roles/cloudflared/defaults/main.yml`:
```yaml
  - hostname: other.travelbesty.store
    service: "http://{{ cloudflared_net_prefix }}.101:8081"
```
Run **homelab-cloudflare-tunnel → apply**. The DNS record and route are created for you.

---

## Troubleshooting

| You see | Cause and fix |
|---|---|
| `zone ... is 'pending'` in the run | Nameservers not switched yet. Finish Part 1 step 3 and wait for **Active**. |
| `401`/`403` from the Cloudflare API in the run | Token missing a permission or scoped to the wrong zone. Recreate it as in Part 1 step 5. |
| Browser: **Error 1033** | The tunnel is not connected. On k8s-w1: `sudo docker logs --tail 30 cloudflared`. |
| Browser: **502 Bad gateway** | The UI is down or the route points to the wrong address. `sudo docker ps` on k8s-w1; `curl -I http://127.0.0.1:8080`. |
| Browser: **404** from Cloudflare | The hostname is not in `cloudflared_routes`. Add it and apply again. |
| Page loads but login loops or fails | Auth service not redeployed with the secure cookie, or `security` missing in `CUSTOMERS`. Redeploy the auth service. |
| "Unknown customer" | `security` is not in `auth_service_customers`. |
| **429** / `503` on login | The rate limit. Wait a minute. |
| Works on the LAN `http://192.168.8.101:8080` but cannot log in | Expected: Secure cookies are not kept over plain HTTP. Use the `https://` name. |

Commands on k8s-w1 (`ssh ubuntu@192.168.8.101`):
```bash
sudo docker ps
sudo docker logs --tail 30 cloudflared
sudo docker logs --tail 30 security-ui
```
