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
11. **Real client IPs.** Measured on Railway: requests reach the container from the edge at `100.64.0.x`, a different address per request, which New API's default trusted-proxy list does not cover. Per-IP rate limits (login, console API) therefore keyed on random edge addresses. `TRUSTED_PROXIES` adds `100.64.0.0/10`; after the change the log shows the caller's public IP and the console API limit (360 requests / 3 min per IP) applied to it.
12. `TZ=UTC`, `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=130` so streaming responses finish during redeploys (New API waits up to 120 s).

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
| `TRUSTED_PROXIES` | `100.64.0.0/10,127.0.0.0/8,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fc00::/7` | Proxies whose `X-Forwarded-For` is trusted; `100.64.0.0/10` is Railway's edge (measured), so rate limits and logs see real client IPs. Empty or invalid falls back to this list. |
| `TZ` | `UTC` | Time zone. |
| `ERROR_LOG_ENABLED` | `true` | Log failed relay requests. |
| `BATCH_UPDATE_ENABLED` | `true` | Batched quota/usage writes. |
| `SYNC_FREQUENCY` | `60` | Cache sync interval in seconds. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `130` | Time for in-flight streams on redeploy. |

Not exposed but honoured: `NEW_API_WAIT_SECONDS` (default 600), every upstream variable (`STREAMING_TIMEOUT`, `GLOBAL_API_RATE_LIMIT`, `TRUSTED_PROXIES`, `NODE_TYPE`, `LOG_SQL_DSN`, ...).

### Postgres, Redis

Verbatim from `_railway-base` (as in 09-litellm): `postgres-ssl:18` with volume `/var/lib/postgresql/data`; `redis:8.2` with password and volume `/data`. No public TCP proxies.

## Resource estimate

Measured on Railway (test project, 2026-11-14, New API rc.51, per-minute `metrics`):

| Service | Idle RAM | Peak seen | CPU | Volume |
|---|---|---|---|---|
| New API | 0.04-0.07 GB | 0.13 GB under load, 0.17 GB during the first-boot / redeploy overlap | < 0.04 vCPU at peak | none |
| Postgres | 0.07-0.10 GB | 0.10 GB | < 0.04 vCPU | grows with usage logs (not measured over time) |
| Redis | 0.03 GB | 0.03 GB | < 0.01 vCPU | < 0.1 GB |
| **Total** | **~0.2 GB** | **~0.3 GB** | | |

Load used: 3,000 requests in 23 s (1,500 token-authenticated `/v1/models`, console API calls, logins). Real provider relays were not measured (no provider key in the test); each in-flight streaming response adds buffers, so busy gateways need more: plan ~0.5 GB for New API at tens of concurrent streams.

- **Idle:** 0.2 GB × $10 + ~0.01 vCPU × $20 + ~0.5 GB volumes × $0.15 ≈ **$2-3/month**.
- **Typical team gateway:** 0.6 GB × $10 + 0.1 vCPU × $20 + 3 GB × $0.15 ≈ **$8-9/month** (provider charges are billed by the providers).
- **Plans:** fits Free (0.5 GB per service) and Trial (1 GB per service) for evaluation; **Hobby recommended** for production (5 GB Postgres volume for logs, no sleep). Pro for replicas and larger volumes.

## Verification checklist

Run on the pre-publish test deploy (2026-11-14) and again after publishing:

1. Deploy log: `root account 'root' created; setup completed on loopback`, then `starting New API on port 3000`; healthcheck `/api/status` 200.
2. `GET /api/setup` → `status: true`; `POST /api/setup` from outside → "The system is already initialized".
3. `POST /api/user/login` as `root` with `NEW_API_ROOT_PASSWORD` → success; with `123456` → "Username or password is incorrect".
4. `POST /api/user/register` → "New user registration has been disabled by administrator".
5. `GET /v1/models` and `POST /v1/chat/completions` without a token or with an invalid token → HTTP 401; with a token created in the console → 200.
6. Deploy log shows the caller's public IP, not `100.64.0.x`.
7. Bad form values (`SESSION_COOKIE_SECURE=maybe`, `SESSION_COOKIE_TRUSTED_URL="not a url, http://x"`, `TRUSTED_PROXIES=garbage,999.1.1.1`, `NEW_API_ROOT_USERNAME="has space"`, `NEW_API_WAIT_SECONDS=soon`): deploy SUCCESS with one warning each.
8. `NEW_API_RESET_ROOT_PASSWORD=true` + new `NEW_API_ROOT_PASSWORD`: log `root password reset for: root`; new password logs in, old one and `123456` do not.
9. Redeploy New API: `setup already recorded in Postgres`, data and logins persist.
10. Unit tests: `bash services/new-api/test/railway-start.test.sh` (68 checks: validators, fallbacks, loopback-only setup, locked setup on an invalid password, reset SQL).

## Open questions

- **Version label in the name.** Upstream ships `v1.0.0-rc.N` as its "Latest" (non-pre-release) channel; there is no final 1.0.0 yet. The listing says "v1". If that reads as a pre-release label to you, drop it ("New API LLM Gateway (Postgres + Redis)"); `idSeed` keeps the service ids.
- **Invalid password on the very first boot** (locked root, random password) is covered by the unit tests with a fake binary, not by a fresh Railway deploy; the reset path that recovers from it was verified on Railway.
- **Relay memory with real providers** was not measured (no provider key used).
- **Upstream release cadence:** a new RC every few days. Re-pin deliberately after reading the notes; rc.50 crashed on CPUs without AVX, fixed in rc.51.
- `NEW_API_RESET_ROOT_PASSWORD=true` left on resets the root password to the variable on every start (harmless, but it overrides password changes made in the console).
