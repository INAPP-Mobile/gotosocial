# GoToSocial on Railway — lightweight, single-binary ActivityPub server.
#
# WHY THIS WRAPPER EXISTS (house-style notes):
#
# - FROM pins the upstream image by tag AND digest, never :latest, so every
#   deploy runs the exact build we tested: superseriousbusiness/gotosocial
#   0.22.3 (release 2026-10-21), manifest-list digest verified against
#   the Docker Hub registry (amd64 manifest digest differs; Railway
#   pulls amd64, and the list digest resolves to it).
# - USER root: the upstream image runs as 1000:1000 (verified in its
#   config blob), which crash-loops with EACCES on Railway's root-owned
#   persistent volume. Running as root keeps the SQLite database, media
#   storage, and wazero cache writable on /data.
# - No PORT baking: GoToSocial listens on GTS_PORT, not Railway's
#   injected PORT, so entrypoint.sh maps PORT -> GTS_PORT at boot
#   (falling back to 8080). A baked port would fight the platform.
# - Env-only config: GoToSocial is fully configurable via GTS_*
#   environment variables (upstream container docs: no config.yaml
#   mount needed), so no config file is generated or mounted.
# - GTS_HOST is a template variable, NOT baked: the instance domain is
#   baked into account URIs at first boot and can never change without
#   breaking federation identity, so it must come from the live
#   RAILWAY_PUBLIC_DOMAIN. The entrypoint fails fast (loud log, no
#   silent localhost) if GTS_HOST is empty or an unresolved ${{...}}
#   expression at boot.
# - First-user seeding lives in entrypoint.sh, not in a README step:
#   GoToSocial has no web signup for the first account on Railway —
#   upstream's documented first-user flow is `admin account create`
#   (plus `promote`), which needs container exec that Railway does not
#   offer. So the entrypoint seeds the admin from template variables
#   on first boot (before the foreground server starts, so the
#   "promotion requires restart" caveat never applies), exactly once,
#   tracked by a marker file on the volume. Two facts shape the
#   sequence (both proven in e2e 2026-10-30): `admin account create`
#   refuses on a fresh database — the instance application must exist
#   first, so the entrypoint boots the server briefly, waits for
#   /api/v1/instance to answer, stops it, then seeds. Admin-created
#   accounts are email-verified by design (upstream fix #1140), so no
#   SMTP round-trip is needed for first login. Web signups remain
#   available as an opt-in: open registration + user-supplied SMTP
#   (see README).
# - No Docker HEALTHCHECK: the Alpine base has busybox but no curl in
#   PATH guarantees; Railway's external healthcheckPath (/) covers it —
#   the landing page is public and unauthenticated.
# - ENTRYPOINT is our script, not the upstream one, because we must map
#   PORT, guard GTS_HOST, and seed the admin first; it then execs the
#   upstream entrypoint command intact: `gotosocial server start`.

FROM superseriousbusiness/gotosocial:0.22.3@sha256:3f36dcf14a4f2e5562122e4783117c48a219d67988f841181b5c2ecaa65d5581

USER root

# Baked defaults (service variables override these at runtime).
# GTS_PORT is deliberately NOT baked: entrypoint.sh maps Railway's
# injected PORT to GTS_PORT at boot. GTS_HOST is deliberately NOT baked:
# it must come from the live RAILWAY_PUBLIC_DOMAIN (template variable).
ENV GTS_DB_TYPE=sqlite \
    GTS_DB_ADDRESS=/data/sqlite.db \
    GTS_STORAGE_BACKEND=local \
    GTS_STORAGE_LOCAL_BASE_PATH=/data/storage \
    GTS_WAZERO_COMPILATION_CACHE=/data/.cache \
    GTS_LETSENCRYPT_ENABLED=false \
    GTS_PROTOCOL=https \
    GTS_ACCOUNTS_REGISTRATION_OPEN=false \
    GTS_ACCOUNTS_APPROVAL_REQUIRED=true \
    GTS_ADMIN_USERNAME=admin \
    GTS_ADMIN_EMAIL=admin@example.com

COPY entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

ENTRYPOINT ["/railway-entrypoint.sh"]

LABEL org.opencontainers.image.source="https://github.com/INAPP-Mobile/gotosocial"
LABEL org.opencontainers.image.title="GoToSocial"
LABEL org.opencontainers.image.description="GoToSocial ActivityPub fediverse server, wrapped for one-click Railway deploys"
