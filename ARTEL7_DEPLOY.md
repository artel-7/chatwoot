# Artel-7 Chatwoot deploy (AA-378)

This fork (`plane-escalation` → `dev` / `prod`) is what we run at
`https://chat.kb-artel.ru` instead of `chatwoot/chatwoot:latest-ce`.

## Branches

| Branch | Image | Action |
|--------|--------|--------|
| `dev` | `ghcr.io/artel-7/chatwoot:dev` (+ `:latest`) | build only |
| `prod` | `ghcr.io/artel-7/chatwoot:prod` | build + pull/recreate on hub1 & hub2 |

Workflow: `.github/workflows/build-image.yml` (self-hosted `a7-builder`).

## Home compose

`infrastructure` `hub1.yml` / `hub2.yml` pin `ghcr.io/artel-7/chatwoot:prod`.
Watchtower is **disabled** for Chatwoot so upstream `:latest-ce` cannot overwrite the fork.

Required host env (same place as `SMTP_*`):

```bash
PLANE_API_KEY=<Plane personal access token>
```

Other Plane vars are hard-coded in compose (workspace `artel7`, project AA).

## First-time / manual cutover

1. Push this repo's `prod` branch (or `workflow_dispatch` on `prod`) and wait for the image.
2. On both hubs, ensure `PLANE_API_KEY` is exported for compose and `infrastructure` is on `home-deploy` with the new image refs.
3. If CI deploy did not run yet:

```bash
cd /home/bob/infrastructure
docker compose -f hub1.yml pull chatwoot-rails chatwoot-sidekiq   # hub2.yml on hub2
docker compose -f hub1.yml up -d --no-deps chatwoot-rails chatwoot-sidekiq
docker compose -f hub1.yml exec -T chatwoot-rails bundle exec rails db:migrate
```

Active Storage proxy (AA-336) is baked into the image
(`config/initializers/active_storage_proxy.rb`); the old bind-mount is removed.
