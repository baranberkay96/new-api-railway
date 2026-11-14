# syntax=docker/dockerfile:1
#
# New API for Railway: the official upstream image, unmodified, plus a start
# script (railway-start.sh, written for this template) that
#   - completes New API's first-run setup on 127.0.0.1 with a generated root
#     password, so the public /setup page is never claimable,
#   - waits for Postgres and Redis on cold start,
#   - replaces invalid deploy-form values with safe defaults instead of failing.
#
# Upstream: https://github.com/QuantumNous/new-api (AGPL-3.0), image
# calciumion/new-api, tag v1.0.0-rc.51 (GitHub "Latest" release, 2026-11-13),
# pinned by multi-arch index digest (checked 2026-11-14).
FROM calciumion/new-api:v1.0.0-rc.51@sha256:d6effcdbc58175494765c0cc5954bdacb2300516eec79ba1a9c61f9b9fae7b49

# psql/pg_isready for the readiness wait, the "already initialized" check and
# the optional root password reset. Debian archive package of the upstream
# base (bookworm), not version-pinned: pinned apt versions disappear from
# mirrors (template STANDARD lesson 27). Retries guard against mirror hiccups.
RUN apt-get -o Acquire::Retries=5 update \
 && apt-get -o Acquire::Retries=5 install -y --no-install-recommends postgresql-client \
 && rm -rf /var/lib/apt/lists/* \
 && psql --version && pg_isready --version

COPY --chmod=0755 railway-start.sh /usr/local/bin/railway-start

ENV PORT=3000
EXPOSE 3000
WORKDIR /data

# Railway runs its own init as PID 1; the script execs New API in the end, so
# SIGTERM reaches New API directly and in-flight streams drain.
ENTRYPOINT ["/usr/local/bin/railway-start"]
