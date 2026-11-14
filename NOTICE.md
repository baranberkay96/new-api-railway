# NOTICE: New API LLM Gateway template

## Software deployed

| Component | Version | Source | Licence | How it is used |
|---|---|---|---|---|
| New API | `v1.0.0-rc.51` (GitHub "Latest" release, 2026-11-13) | Docker Hub `calciumion/new-api:v1.0.0-rc.51@sha256:d6effcdbc58175494765c0cc5954bdacb2300516eec79ba1a9c61f9b9fae7b49` (multi-arch index, published by the New API maintainers' CI). Source: https://github.com/QuantumNous/new-api/tree/v1.0.0-rc.51 | GNU Affero General Public License v3.0, with additional terms under AGPLv3 section 7 (see below). Copyright (c) QuantumNous and contributors. The image ships `LICENSE`, `NOTICE` and `THIRD-PARTY-LICENSES.md` in `/licenses/`. | **Unmodified.** The upstream binary `/new-api` runs as published; no upstream file is changed, patched or rebuilt. |
| PostgreSQL client (`psql`, `pg_isready`) | Debian bookworm `postgresql-client` | Debian archive, installed on top of the upstream image | PostgreSQL License | Readiness wait, the "already initialized" check, the first-start registration setting and the optional root password reset |
| PostgreSQL server | 18 | `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway) | PostgreSQL License | Database service |
| Redis | 8.2 | `redis:8.2` (Docker official image) | RSALv2 / SSPLv1 / AGPLv3 (Redis 8) | Cache and multi-replica sync |

### AGPL-3.0 and where to get the source

New API is free software under the AGPL-3.0. This template deploys the upstream image without modification. The complete corresponding source of the deployed version is at https://github.com/QuantumNous/new-api/tree/v1.0.0-rc.51 and the licence text at https://github.com/QuantumNous/new-api/blob/v1.0.0-rc.51/LICENSE.

Upstream's `NOTICE` adds terms under AGPLv3 section 7: modified versions must keep the attribution "Frontend design and development by New API contributors." and a visible link to https://github.com/QuantumNous/new-api in the user interface. The unmodified image keeps both. If you modify New API and offer it to users over a network, the AGPL requires you to offer them your modified source, and these attribution terms apply.

## Written for this template

These files were written for this template and are not part of New API: `services/new-api/Dockerfile`, `services/new-api/railway-start.sh`, `services/new-api/test/railway-start.test.sh`, `template.json`, `TEMPLATE.md`, `README.md` and this file. They are a separate work that starts and configures New API from the outside: the start script only sets environment variables, waits for the databases, calls New API's own `/api/setup` endpoint on 127.0.0.1, writes one setting (`RegisterEnabled`) through SQL on the first start and, when asked, resets the root password hash through SQL (pgcrypto bcrypt, a format New API accepts). It contains no New API code. Postgres and Redis service definitions are copied from this repository's `_railway-base` files (Railway's own templates).

The icon is New API's logo, `web/public/logo.png` at tag `v1.0.0-rc.51`, referenced by URL on jsDelivr. It identifies the software the template deploys.

## Upstream sources checked (2026-11-14, read only; nothing was executed locally)

| What | Source | Version |
|---|---|---|
| Release list and "Latest" flag | `gh api repos/QuantumNous/new-api/releases`, `releases/latest` | `v1.0.0-rc.51`; last non-RC release `v0.13.2` (2026-04-27) |
| Image tag and digest | Docker Hub registry API, `calciumion/new-api` manifests for `v1.0.0-rc.51` and `latest` (same digest) | 2026-11-14 |
| Image build | `Dockerfile` (debian bookworm-slim, `ENTRYPOINT ["/new-api"]`, `WORKDIR /data`, port 3000) | `v1.0.0-rc.51` |
| Reference stack | `docker-compose.yml` (Postgres + Redis, `/api/status` healthcheck, env list) | `v1.0.0-rc.51` |
| First-run behaviour | `model/main.go` (`CheckSetup`; the old `root`/`123456` account creation `createRootAccountIfNeed` is no longer called), `controller/setup.go` (unauthenticated `POST /api/setup` creates the root user while the system is uninitialized), `router/api-router.go` | `v1.0.0-rc.51` |
| Password rules and hashing | `common/account_password.go` (8-128 characters, Argon2id; bcrypt hashes still verified), `common/crypto.go` | `v1.0.0-rc.51` |
| Environment variables | `common/init.go`, `common/session_cookie.go` (exits on invalid `SESSION_COOKIE_*`), `common/redis.go` (exits if Redis does not answer within 5 s), `main.go` (`HOST`, `PORT`, `--log-dir`) | `v1.0.0-rc.51` |
| Licence terms | `LICENSE`, `NOTICE`, README "License" section | `v1.0.0-rc.51` |

## Market templates reviewed

| Template | Source | Use |
|---|---|---|
| `new-api` ("New API") | `calciumion/new-api:latest`, Postgres, Redis | Read for comparison only. Nothing copied. |
| `newapi` | `dielect/newapi-railway-template`, Postgres 17, Redis | Read for comparison only. Nothing copied. |
| `new-api-template` | `lNamelessl/new-api-railway-template`, MySQL, Redis | Read for comparison only. Nothing copied. |
| `new-api-gateway` | `two-workspaces/new-api`, Postgres | Read for comparison only. Nothing copied. |

## Names and affiliation

New API is a project of QuantumNous and contributors; OpenAI, Claude/Anthropic, Gemini/Google and other provider names belong to their owners. This is a community template; it is not affiliated with, sponsored or endorsed by QuantumNous, the New API contributors, any model provider or Railway.
