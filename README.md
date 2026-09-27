# gentlebirth.shared.caddy

The single source of truth for Caddy on the shared Contabo host (`89.117.17.81`,
Ubuntu 24.04, Caddy 2.11.4). Every public hostname and route served by that host
lives here. No other repository writes `/etc/caddy`.

## Layout

| Path | Installed as | Purpose |
|---|---|---|
| `Caddyfile` | `/etc/caddy/Caddyfile` | Imports every site file |
| `sites/<hostname>.caddy` | `/etc/caddy/sites/` | One site block per public hostname |
| `checks.txt` | not installed | Public route probes run around every deploy |
| `scripts/apply-caddy.sh` | run on the host | Validate, reload, restore previous config on failure |
| `scripts/check-routes.sh` | run in CI | Probes the routes in `checks.txt` |

## Current routes (`api.mancebo.ai`)

| Path | Upstream | Owner |
|---|---|---|
| `/course-mcp/*` (prefix stripped) | `127.0.0.1:8082` | mancebo: Course Engineer MCP |
| `/search-mcp/*` (prefix stripped) | `127.0.0.1:8084` | mancebo: search MCP |
| `/gentlebirth-mcp/*` (prefix stripped) | `127.0.0.1:8085` | gentlebirth.peritanal.advisor: Perinatal MCP |
| `/mcp`, `/mcp/*` | `127.0.0.1:8081` | mancebo: Supabase MCP |
| everything else | `127.0.0.1:8080` | mancebo: control plane |

## Adding a route for a new app

1. Deploy the app so it listens on a free loopback port (check `ss -ltn` on the host).
2. Add a `handle_path /<app>/*` block to the right site file (or a new `sites/<hostname>.caddy`; new hostnames also need a DNS record pointing at the host).
3. Add probes for the route to `checks.txt`.
4. Open a PR. CI validates and format-checks with the host's Caddy version.
5. Merge to `main`. CI probes all routes, uploads, runs `apply-caddy.sh`, probes again, and rolls back if a route that passed before now fails.

## CI/CD configuration

- Repository variables: `CONTABO_HOST`, `CONTABO_SSH_USER`, `CONTABO_HOST_KEY_FINGERPRINT` (the host key is pinned; a mismatch aborts).
- Repository secret: `CONTABO_SSH_PRIVATE_KEY`.
- The `production` environment gates the deploy job; add required reviewers there if you want a manual approval.
- This repository is public. Secrets are never exposed to pull requests from forks, and only pushes to `main` deploy.

## Manual break-glass

```sh
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy
# Previous config from the last deploy:
sudo rm -rf /etc/caddy && sudo cp -a /etc/caddy.previous /etc/caddy && sudo systemctl reload caddy
```
