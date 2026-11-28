# Auth service → k8s-w1 (Docker)

Workflow: **Actions → homelab-services → Run workflow → service `auth-service`**

```
GitHub secrets ─► workflow step env ─► docker run toolbox (on vm-runner) ─► ansible services.yml
                                          └─ play 3: add VM <NET_PREFIX>.101 → role auth_service
                                               SSH ubuntu@k8s-w1: install Docker → docker login ghcr.io
                                               → docker run auth-service (port 9081) → wait for /actuator/health
```

Nothing is installed or scripted on vm-runner: it only runs the toolbox container.
The image itself is built and pushed by the **service's own repo** (`dearlavion-spring-authentication-service`,
tag `:dev`). This repo only pulls and runs it.

## One-time setup (repo → Settings → Secrets and variables → Actions)

| Type | Name | Value |
|---|---|---|
| Secret | `AUTH_MONGODB_URI` | Atlas connection string |
| Secret | `AUTH_JWT_SECRET` | base64 HMAC key (same one other services verify with) |
| Secret | `AUTH_SERVICE_KEY` | shared key for `/auth/internal/*` (can be empty) |
| Secret | `AUTH_PROVISION_SECRET` | needed to create ADMIN/STAFF (can be empty) |
| Secret | `AUTH_SMTP_USERNAME` | Gmail address that sends superadmin password reset emails (can be empty: no emails) |
| Secret | `AUTH_SMTP_PASSWORD` | Gmail app password for that address, without spaces (can be empty: no emails) |
| Secret | `GHCR_TOKEN` | **read-only** PAT with `read:packages` for the image |
| Variable | `GHCR_USER` | GitHub user that owns that token |

Other settings (tenants, Kafka, cookie path, memory, image tag) are in
`ansible/roles/auth_service/defaults/main.yml`.

## Check it

```bash
curl http://192.168.8.101:9081/actuator/health      # from the LAN
ssh ubuntu@192.168.8.101 'sudo docker logs --tail 50 auth-service'
```

Redeploy after a new image: run the same workflow again (`pull: always` replaces the container).
