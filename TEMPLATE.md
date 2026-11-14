# New API v1 LLM Gateway (Postgres + Redis): Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **New API v1 LLM Gateway (Postgres + Redis)** (41 chars). "v1" is the release line upstream ships as GitHub "Latest" (`v1.0.0-rc.N` since April 2026); see Open questions. |
| Description | Self-hosted LLM gateway for OpenAI, Claude and Gemini with keys and quotas. (75 chars) |
| Category | AI/ML |
| Tags | new-api, llm, ai-gateway, openai-compatible, claude, gemini, api-keys, quotas, one-api |
| Icon | `https://cdn.jsdelivr.net/gh/QuantumNous/new-api@v1.0.0-rc.51/web/public/logo.png` (200, image/png) |
| Repo | `baranberkay96/new-api-railway`, service root `/services/new-api` |

## Base market templates (checked 2026-11-14)

| Code | Name | Active / recent / total projects | Stack | Problems |
|---|---|---|---|---|
| `new-api` | New API | 49 / 31 / 89 | `calciumion/new-api:latest`, Postgres 18, Redis 8.2 | Unpinned `latest`; no `SESSION_SECRET` (logins reset on restart); no healthcheck; open setup wizard; `TZ=Asia/Shanghai` |
| `newapi` | newapi | 56 / 11 / 94 | repo `dielect/newapi-railway-template`, Postgres 17, Redis 8.2 | Open setup wizard; public TCP proxies on Postgres/Redis |
| `new-api-template` | new-api-template | 3 / 8 / 8 | repo build, MySQL 8.4, Redis 7.4 without volume | Open setup wizard |
| `new-api-gateway` | New API (One API fork) | 2 / 2 / 2 | fork `two-workspaces/new-api`, Postgres | Runs a fork, not upstream |

Kept from the market: Postgres + Redis topology, `/api/status` healthcheck, `BATCH_UPDATE_ENABLED`, `ERROR_LOG_ENABLED`, Railway base Postgres/Redis definitions. Nothing copied (no licence on those repos).

## Improvements over market templates

1. **Pinned version:** official image `calciumion/new-api:v1.0.0-rc.51` by digest instead of `latest` or a fork.
2. **No claimable setup page.** Upstream leaves a fresh instance uninitialized and lets the first visitor of `/setup` (`POST /api/setup`, unauthenticated) create the root user. All market templates expose that page until the owner gets there first. Here the start script boots New API on 127.0.0.1, completes the setup with `NEW_API_ROOT_USERNAME` / generated `NEW_API_ROOT_PASSWORD`, stops it and only then starts it on the public port.
3. **No known default password.** Upstream's old `root` / `123456` bootstrap is not used by current releases, and nothing in this template creates it.
4. **Generated `SESSION_SECRET` and `CRYPTO_SECRET`:** logins survive restarts and work across replicas.
5. **Secure session cookies with origin check** (`SESSION_COOKIE_SECURE=true`, trusted origin = the Railway domain, extendable).
6. **Self-registration closed on first start** (`NEW_API_REGISTER_ENABLED=false`), so a public gateway does not collect anonymous accounts.
7. **Root password reset** without database tools (`NEW_API_RESET_ROOT_PASSWORD=true`).
8. **Cold-start safe:** waits up to 10 minutes for Postgres (`pg_isready`) and Redis (TCP); New API itself exits if either is missing.
9. **Deploy-form values never fail the deploy** (STANDARD rule 29): invalid port, username, password, cookie flag or origin list fall back to safe values with a log warning; an unusable root password locks the account with a random password and the log explains the reset.
10. **No file logs on ephemeral disk** (`--log-dir=`): logs go to Railway's log view; no volume needed for New API.
11. `TZ=UTC`, `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=130` so streaming responses finish during redeploys (New API waits up to 120 s).

## Pinned versions

| Service | Source | Version | Released | Checked |
|---|---|---|---|---|
| New API | `calciumion/new-api:v1.0.0-rc.51@sha256:d6effcdbc58175494765c0cc5954bdacb2300516eec79ba1a9c61f9b9fae7b49` (via `services/new-api/Dockerfile`) | v1.0.0-rc.51 | 2026-11-13 | 2026-11-14 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl:18` | 18 | Railway base | 2026-11-14 |
| Redis | `redis:8.2` | 8.2 | Railway base | 2026-11-14 |

Upstream has published only `v1.0.0-rc.N` releases since 2026-04-28 (51 so far), each marked "Latest" (not pre-release) on GitHub; `latest` on Docker Hub points to the same digest. The last non-RC release, `v0.13.2` (2026-04-27), is seven months older and lacks the current security fixes, so the RC line is what upstream ships as stable. rc.51 fixes a crash of rc.50 on x86-64 CPUs without AVX (Railway hosts have AVX).

## Architecture

```
clients (OpenAI / Claude / Gemini SDKs, coding tools, chat UIs)
        │ HTTPS  /v1/...  /v1/messages  /v1beta/...   + web console
        ▼
Railway edge ──► [New API :3000]  (railway-start → exec /new-api, upstream binary)
                    │ pgx (SQL_DSN)          │ go-redis (REDIS_CONN_STRING)
                    ▼                        ▼
               [Postgres :5432]          [Redis :6379]
                    volume                  volume
New API ──► model providers (OpenAI, Anthropic, Google, ...) over the internet
```

Start sequence of `railway-start`:

1. Sanitize deploy-form values (port, secrets, cookie settings, root username/password).
2. Wait for Postgres (`pg_isready`) and Redis (TCP) up to `NEW_API_WAIT_SECONDS` (600).
3. If Postgres has no `setups` row: start New API with `HOST=127.0.0.1`, wait for `/api/status`, `POST /api/setup` with the root credentials, stop it. Up to 5 attempts; if setup never succeeds the script exits non-zero instead of exposing an uninitialized instance.
4. First start only: store `RegisterEnabled` from `NEW_API_REGISTER_ENABLED`.
5. If `NEW_API_RESET_ROOT_PASSWORD=true`: set the root user's password hash (pgcrypto bcrypt) to `NEW_API_ROOT_PASSWORD`.
6. `exec /new-api --log-dir=` on `[::]:$PORT` (dual-stack). `NEW_API_ROOT_PASSWORD` is removed from New API's environment.

## Services

### New API

- Source: repo `baranberkay96/new-api-railway`, root `/services/new-api` (Dockerfile: upstream image + `postgresql-client` + `railway-start`)
- Healthcheck `/api/status`, timeout 900 s; public domain, target port 3000; no TCP proxy; no volume
- Restart policy ON_FAILURE (10 retries); replicas 1

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | HTTP port of the API and web console (public domain target). |
| `SQL_DSN` | `${{Postgres.DATABASE_URL}}` | Postgres for users, tokens, channels, quotas and logs. |
| `REDIS_CONN_STRING` | `${{Redis.REDIS_URL}}` | Redis for caches, rate limits and multi-replica sync. |
| `NEW_API_ROOT_USERNAME` | `root` | Root login name, 1-12 characters, used on the first start. |
| `NEW_API_ROOT_PASSWORD` | `${{secret(24, alnum)}}` | Root password (8-128 characters), set on the first start. |
| `NEW_API_RESET_ROOT_PASSWORD` | `false` | `true` = reset the root password to `NEW_API_ROOT_PASSWORD` on the next start. |
| `NEW_API_REGISTER_ENABLED` | `false` | Self-registration on the first start. |
| `SESSION_SECRET` | `${{secret(64, hex)}}` | Signs login sessions. |
| `CRYPTO_SECRET` | `${{secret(64, hex)}}` | Key for New API's internal HMACs. |
| `SESSION_COOKIE_SECURE` | `true` | Secure cookies + origin check on refresh/logout. |
| `SESSION_COOKIE_TRUSTED_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Allowed console origins, comma-separated; the Railway domain is always added. |
| `TZ` | `UTC` | Time zone. |
| `ERROR_LOG_ENABLED` | `true` | Log failed relay requests. |
| `BATCH_UPDATE_ENABLED` | `true` | Batched quota/usage writes. |
| `SYNC_FREQUENCY` | `60` | Cache sync interval in seconds. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `130` | Time for in-flight streams on redeploy. |

Not exposed but honoured: `NEW_API_WAIT_SECONDS` (default 600), every upstream variable (`STREAMING_TIMEOUT`, `GLOBAL_API_RATE_LIMIT`, `TRUSTED_PROXIES`, `NODE_TYPE`, `LOG_SQL_DSN`, ...).

### Postgres, Redis

Verbatim from `_railway-base` (as in 09-litellm): `postgres-ssl:18` with volume `/var/lib/postgresql/data`; `redis:8.2` with password and volume `/data`. No public TCP proxies.

## Resource estimate

RESOURCES_PLACEHOLDER

## Verification checklist

VERIFY_PLACEHOLDER

## Open questions

OPEN_PLACEHOLDER
