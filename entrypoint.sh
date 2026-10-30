#!/bin/sh
# GoToSocial entrypoint for Railway — see Dockerfile header for the why.
set -e

# All persistent state lives on the Railway volume mounted at /data.
mkdir -p /data/storage /data/.cache

# GoToSocial listens on GTS_PORT, not Railway's injected PORT. Map it at
# boot (8080 fallback matches the upstream container default).
export GTS_PORT="${PORT:-8080}"
echo "[entrypoint] listening on port ${GTS_PORT}."

# GTS_HOST is the instance's permanent federation identity: it is baked
# into account URIs at first boot and cannot change later without
# breaking federation. Fail fast and loud if it is missing or an
# unresolved ${{...}} expression — a silent localhost default would
# create a broken instance that looks healthy.
case "${GTS_HOST:-}" in
  ""|*'${{'*)
    echo "[entrypoint] FATAL: GTS_HOST is not set to a real domain (got '${GTS_HOST:-<empty>}')."
    echo "[entrypoint] The service needs its Railway public domain before first boot; attach a domain and redeploy."
    exit 1
    ;;
  *)
    echo "[entrypoint] instance host: ${GTS_HOST}."
    ;;
esac

# First-boot admin seeding (exactly once, marker on the volume).
# Upstream's documented first-user flow is `admin account create` +
# `promote`, which needs container exec that Railway does not offer,
# so the entrypoint does it before the server ever runs (promotion
# therefore needs no restart). Admin-created accounts are
# email-verified by design, so first login needs no SMTP.
# Credentials come from template variables: GTS_ADMIN_USERNAME and
# GTS_ADMIN_EMAIL baked as Dockerfile defaults, GTS_ADMIN_PASSWORD as a
# generated template secret. Change the password in the settings panel
# after first login.
if [ ! -f /data/.admin-seeded ] && [ -n "${GTS_ADMIN_PASSWORD:-}" ]; then
  echo "[entrypoint] seeding first admin account '${GTS_ADMIN_USERNAME:-admin}'..."
  if /gotosocial/gotosocial admin account create \
      --username "${GTS_ADMIN_USERNAME:-admin}" \
      --email "${GTS_ADMIN_EMAIL:-admin@example.com}" \
      --password "${GTS_ADMIN_PASSWORD}"; then
    echo "[entrypoint] admin account created."
  else
    echo "[entrypoint] NOTE: admin create failed (account may already exist); continuing to promote."
  fi
  if /gotosocial/gotosocial admin account promote \
      --username "${GTS_ADMIN_USERNAME:-admin}"; then
    touch /data/.admin-seeded
    echo "[entrypoint] admin promoted and seeding marked complete."
  else
    echo "[entrypoint] WARNING: admin promote failed; seeding will retry on next restart."
  fi
elif [ -f /data/.admin-seeded ]; then
  echo "[entrypoint] admin already seeded; skipping."
else
  echo "[entrypoint] WARNING: GTS_ADMIN_PASSWORD unset; no admin seeded. Set it and redeploy, or use web signup with SMTP."
fi

# Chain into the upstream server (its image entrypoint is
# `gotosocial server start`; we exec it directly).
echo "[entrypoint] starting gotosocial..."
exec /gotosocial/gotosocial server start
