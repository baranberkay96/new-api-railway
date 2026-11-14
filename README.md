# Deploy and Host New API with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/new-api-v1-llm-gateway-postgres-redis?referralCode=20H68q)

New API is an open-source, self-hosted LLM gateway. It puts OpenAI, Claude, Gemini and many other model providers behind OpenAI-, Claude- and Gemini-compatible APIs, with users, API tokens, quotas and usage logs. This community template runs the official New API image with Postgres and Redis, a pinned version and a protected first start.

## About Hosting New API

New API is a single Go service with a web console. Without configuration it falls back to SQLite on the container disk, signs sessions with a key that changes on every restart, and leaves a fresh instance uninitialized: whoever opens the setup page first becomes the root admin. This template fixes all three. Data lives in Postgres, Redis handles caching and multi-replica sync, and session and crypto keys are generated at deploy. Before the public port opens, a start script completes the setup on 127.0.0.1 with a generated root password, so the setup page is never exposed. The upstream image runs unmodified.

## Common Use Cases

- One internal endpoint for OpenAI, Claude and Gemini models, with a separate API token, quota and model list per team or application
- Load balancing and failover across several provider keys or channels of the same model, with automatic channel tests
- Usage and cost tracking per user, token, model and channel
- Serving OpenAI-, Claude- and Gemini-format clients (SDKs, coding assistants, chat UIs) from the same gateway

## Dependencies for New API Hosting

- New API `v1.0.0-rc.51`, official image `calciumion/new-api`, pinned by digest (AGPL-3.0)
- PostgreSQL 18 (Railway Postgres)
- Redis 8.2 (Railway Redis)
- API keys or accounts for the model providers you connect, added in the console

### Deployment Dependencies

- Source, releases and licence: https://github.com/QuantumNous/new-api
- Documentation: https://docs.newapi.pro
- Environment variables: https://docs.newapi.pro/en/docs/installation/config-maintenance/environment-variables
- Railway Fair Use Policy: https://railway.com/legal/fair-use

### Implementation Details

| Service | Role | Public | Storage |
|---|---|---|---|
| New API | API (`/v1`, `/v1/messages`, `/v1beta`), web console, health `/api/status` | Yes, port 3000 | none (all data in Postgres) |
| Postgres | Users, tokens, channels, quotas, usage logs | No | Volume |
| Redis | Caches, rate limits, sync between replicas | No | Volume |

**First login**

1. Wait until the New API deployment is active (healthcheck `/api/status`).
2. Open `https://{your-domain}` and sign in as `root` (`NEW_API_ROOT_USERNAME`) with `NEW_API_ROOT_PASSWORD` from the New API service's Variables tab. The default upstream password `123456` does not exist here.
3. Add a channel (a provider and your key), then create an API token and call `https://{your-domain}/v1/chat/completions` with `Authorization: Bearer {token}`. Requests without a valid token get HTTP 401.

Self-registration starts **closed** (`NEW_API_REGISTER_ENABLED=false`): the root user creates accounts. Open it under Settings if you run a shared gateway.

**Lost root password:** set `NEW_API_ROOT_PASSWORD` to a new value (8-72 characters), set `NEW_API_RESET_ROOT_PASSWORD=true`, redeploy, log in, then set the reset variable back to `false`.

**Client IPs:** `TRUSTED_PROXIES` includes Railway's edge (`100.64.0.0/10`), so rate limits and logs see real client IPs.

**Custom domain:** add `https://{your-custom-domain}` to `SESSION_COOKIE_TRUSTED_URL` (comma-separated), otherwise logins from that domain are signed out when their session refreshes.

**Resources and plans:** measured on Railway, the stack idles at about 0.2 GB RAM in total (New API 0.04-0.07 GB, Postgres 0.07-0.10 GB, Redis 0.03 GB) and New API peaked at 0.13 GB under a burst of 3,000 authenticated requests. It fits the Free and Trial plans for evaluation; use Hobby or Pro for production, where the Postgres volume holds the growing usage logs. Busy gateways with many concurrent streams need more memory.

**Scaling:** raise replicas on the New API service. Redis and the shared `SESSION_SECRET` keep sessions, caches and settings consistent across replicas. Long streaming responses finish during redeploys (`RAILWAY_DEPLOYMENT_DRAINING_SECONDS`).

**Pinning and upgrades:** the version is the `FROM` line in `services/new-api/Dockerfile` (tag plus digest). Upstream publishes its stable channel as `v1.0.0-rc.N` releases; read the release notes, change tag and digest, and redeploy. Tables migrate on start. Back up Postgres first.

**Use it lawfully:** connect only provider accounts and API keys you are entitled to use, and follow each provider's terms. Railway's Fair Use Policy forbids reselling Railway compute, evading usage limits and running proxy or anonymization services; a gateway for your own teams and applications is the intended use. Commercial or resale use of model access is your responsibility under your providers' terms and applicable law; get professional advice if unsure.

### Why Deploy New API on Railway?

Railway gives New API a public HTTPS domain, private networking to its Postgres and Redis, generated secrets and usage-based billing. Other services in the project can call the gateway privately at `http://${{New API.RAILWAY_PRIVATE_DOMAIN}}:3000`, replicas are one setting, and upgrades are a one-line tag change.
