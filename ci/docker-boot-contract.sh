#!/usr/bin/env bash
#
# Boot contract for the image built from ./Dockerfile.
#
# Everything downstream of this image — the OSS docker-compose, the Helm
# charts, the migrate Job — picks which process to run by overriding the
# container command. That only works while the image keeps three promises:
#
#   1. no ENTRYPOINT, so an override replaces the command instead of becoming
#      an argument to it
#   2. a default CMD, so `docker run <image>` with no override still boots
#   3. an HTTP client on PATH, so the healthchecks that gate `compose up
#      --wait` can run from inside the container
#
# v1.54.0 broke 1 and 3 at once, via a base image change, with no signal from
# any test in this repo. Hence this script.
#
# Usage: ci/docker-boot-contract.sh <image-ref>
#
# Requires a reachable Postgres and Redis. CI leans on the default
# DOCKER_NETWORK=host, which puts the containers in the runner's own network
# namespace alongside the service containers. Docker Desktop does not give you
# that, so locally point the containers at a bridge network instead:
#
#   docker network create lago-boot
#   docker run -d --name pg --network lago-boot \
#     -e POSTGRES_DB=lago -e POSTGRES_USER=lago -e POSTGRES_PASSWORD=lago \
#     getlago/postgres-partman:15.0-alpine
#   docker run -d --name redis --network lago-boot redis:7-alpine
#   DOCKER_NETWORK=lago-boot \
#   DATABASE_URL=postgresql://lago:lago@pg:5432/lago \
#   REDIS_URL=redis://redis:6379 \
#   LAGO_RSA_PRIVATE_KEY="$(openssl genrsa 2048 | openssl base64 -A)" \
#   ci/docker-boot-contract.sh <image-ref>

set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref>}"
NET="${DOCKER_NETWORK:-host}"

DATABASE_URL="${DATABASE_URL:-postgresql://lago:lago@127.0.0.1:5432/lago}"
REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379}"

API_PORT="${API_PORT:-3000}"
WORKER_PORT="${WORKER_PORT:-8080}"

# A one-shot container that is supposed to exit must be bounded. The failure
# this script guards against does not look like an error — migrate.sh gets
# swallowed and Puma boots in its place, so the container runs happily forever.
# Unbounded, the test would reproduce the four-hour CI hang instead of
# reporting it.
RUN_DEADLINE="${RUN_DEADLINE:-900}"
BOOT_DEADLINE="${BOOT_DEADLINE:-120}"

failures=0
cleanup_containers=()

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() {
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  failures=$((failures + 1))
}
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

cleanup() {
  for c in "${cleanup_containers[@]:-}"; do
    [ -n "$c" ] || continue
    docker logs "$c" >"/tmp/${c}.log" 2>&1 || true
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Run a container to completion under a deadline. Echoes its exit status, or
# 124 (the `timeout` convention) if it was still running when time ran out.
# `timeout` itself is not portable enough to rely on — it is absent from a
# stock macOS, where this script also has to run.
run_bounded() {
  local name=$1
  shift
  cleanup_containers+=("$name")
  docker run -d --name "$name" "$@" >/dev/null
  local waited=0
  while [ "$waited" -lt "$RUN_DEADLINE" ]; do
    if [ "$(docker inspect "$name" --format '{{.State.Running}}')" != "true" ]; then
      docker inspect "$name" --format '{{.State.ExitCode}}'
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  docker kill "$name" >/dev/null 2>&1 || true
  echo 124
}

# Poll an HTTP endpoint from *inside* the container, which is what the compose
# healthchecks do. Returns non-zero if it never answers, or if the container
# dies first.
wait_healthy() {
  local name=$1 url=$2 waited=0
  while [ "$waited" -lt "$BOOT_DEADLINE" ]; do
    if docker exec "$name" curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    [ "$(docker inspect "$name" --format '{{.State.Running}}')" = "true" ] || return 1
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

# Mirrors the OSS docker-compose backend environment closely enough to boot.
# LAGO_CREATE_ORG is deliberately on: it is the path that regressed, because it
# is the only one that writes to `roles`.
docker_env=(
  -e "DATABASE_URL=$DATABASE_URL"
  -e "REDIS_URL=$REDIS_URL"
  -e "LAGO_REDIS_CACHE_URL=$REDIS_URL"
  -e "RAILS_ENV=production"
  -e "RAILS_LOG_TO_STDOUT=true"
  -e "SECRET_KEY_BASE=ci-secret-key-base-hex-64"
  -e "LAGO_RSA_PRIVATE_KEY=${LAGO_RSA_PRIVATE_KEY:?LAGO_RSA_PRIVATE_KEY must be set}"
  -e "LAGO_ENCRYPTION_PRIMARY_KEY=ci-encryption-primary-key"
  -e "LAGO_ENCRYPTION_DETERMINISTIC_KEY=ci-encryption-deterministic-key"
  -e "LAGO_ENCRYPTION_KEY_DERIVATION_SALT=ci-encryption-derivation-salt"
  -e "LAGO_API_URL=http://localhost:${API_PORT}"
  -e "LAGO_FRONT_URL=http://localhost"
  -e "LAGO_PDF_URL=http://localhost:3001"
  -e "LAGO_DISABLE_SEGMENT=true"
  -e "LAGO_CREATE_ORG=true"
  -e "LAGO_ORG_NAME=Lago"
  -e "LAGO_ORG_USER_EMAIL=foo@bar.com"
  -e "LAGO_ORG_USER_PASSWORD=foobar"
  -e "LAGO_ORG_API_KEY=ci-boot-contract"
)

# --------------------------------------------------------------------------
section "Image config"
# --------------------------------------------------------------------------

entrypoint=$(docker image inspect "$IMAGE" --format '{{json .Config.Entrypoint}}')
if [ "$entrypoint" = "null" ] || [ "$entrypoint" = "[]" ]; then
  pass "no ENTRYPOINT (command overrides replace, not append)"
else
  fail "ENTRYPOINT is $entrypoint — every downstream command: becomes an argument to it"
fi

cmd=$(docker image inspect "$IMAGE" --format '{{json .Config.Cmd}}')
if [ "$cmd" != "null" ] && [ "$cmd" != "[]" ]; then
  pass "default CMD is $cmd"
else
  fail "no default CMD — \`docker run $IMAGE\` with no override has nothing to run"
fi

if docker run --rm --entrypoint "" "$IMAGE" /bin/sh -c 'command -v curl' >/dev/null 2>&1; then
  pass "curl on PATH (compose healthchecks can run)"
else
  fail "curl missing — the api and api-worker healthchecks cannot run, so compose up --wait never completes"
fi

# --------------------------------------------------------------------------
section "Command override reaches the script"
# --------------------------------------------------------------------------

# The regression in a single assertion, and deliberately no --entrypoint flag
# here: this is exactly what compose and k8s do. With an ENTRYPOINT present,
# Path stays the entrypoint and the override is demoted into Args —
#   Path=/app/scripts/start.sh  Args=["./scripts/migrate.sh"]
# — which is how `migrate` came to boot Puma.
probe=$(docker create "$IMAGE" ./scripts/migrate.sh)
path=$(docker inspect "$probe" --format '{{.Path}}')
args=$(docker inspect "$probe" --format '{{json .Args}}')
docker rm -f "$probe" >/dev/null
if [ "$path" = "./scripts/migrate.sh" ]; then
  pass "an override becomes the container's Path"
else
  fail "override was demoted to an argument: Path=$path Args=$args"
fi

# --------------------------------------------------------------------------
section "migrate.sh boots, seeds and exits"
# --------------------------------------------------------------------------

# This is the compose `migrate` service verbatim. It has to exit 0, or the
# service_completed_successfully gate holds every other service down.
migrate_status=$(run_bounded lago-boot-migrate --network "$NET" "${docker_env[@]}" "$IMAGE" ./scripts/migrate.sh)
case "$migrate_status" in
0)
  pass "./scripts/migrate.sh exited 0"
  ;;
124)
  fail "./scripts/migrate.sh never exited (${RUN_DEADLINE}s) — the v1.54.0 failure mode: the override was ignored and a long-running process booted instead"
  docker logs lago-boot-migrate 2>&1 | tail -40
  ;;
*)
  fail "./scripts/migrate.sh exited $migrate_status"
  docker logs lago-boot-migrate 2>&1 | tail -40
  ;;
esac

# roles:seed_predefined must land before signup:seed_organization, which looks
# the admin role up by `admin: true` alone and would otherwise insert a Role
# with a NULL code.
roles_status=$(run_bounded lago-boot-roles --network "$NET" "${docker_env[@]}" "$IMAGE" \
  bundle exec rails runner 'puts "ROLES=" + Role.where(organization_id: nil).order(:code).pluck(:code).join(",")')
roles=$(docker logs lago-boot-roles 2>/dev/null | sed -n 's/^ROLES=//p' | tail -1)
if [ "$roles_status" = "0" ] && [ "$roles" = "admin,finance,manager" ]; then
  pass "predefined roles seeded ($roles)"
else
  fail "predefined roles are '$roles', expected 'admin,finance,manager'"
fi

# --------------------------------------------------------------------------
section "start.api.sh boots and answers its own healthcheck"
# --------------------------------------------------------------------------

cleanup_containers+=("lago-boot-api")
docker run -d --name lago-boot-api --network "$NET" \
  "${docker_env[@]}" "$IMAGE" ./scripts/start.api.sh >/dev/null

# Run the compose healthcheck command inside the container, which is the thing
# that actually regressed — the API itself was healthy from the host all along.
if wait_healthy lago-boot-api "http://localhost:${API_PORT}/health"; then
  pass "in-container 'curl -f http://localhost:${API_PORT}/health' succeeds"
else
  fail "api never answered its own healthcheck"
  docker logs lago-boot-api 2>&1 | tail -40
fi

# --------------------------------------------------------------------------
section "start.worker.sh boots and answers its own healthcheck"
# --------------------------------------------------------------------------

cleanup_containers+=("lago-boot-worker")
docker run -d --name lago-boot-worker --network "$NET" \
  "${docker_env[@]}" "$IMAGE" ./scripts/start.worker.sh >/dev/null

if wait_healthy lago-boot-worker "http://localhost:${WORKER_PORT}"; then
  pass "in-container 'curl -f http://localhost:${WORKER_PORT}' succeeds"
else
  fail "worker never answered its own healthcheck"
  docker logs lago-boot-worker 2>&1 | tail -40
fi

# --------------------------------------------------------------------------
section "default CMD bootstraps an empty database"
# --------------------------------------------------------------------------

# Deliberately a *second, empty* database. start.sh migrates and seeds from
# scratch before booting Puma, and that path is not covered by anything above —
# it is the one lago-dev-us-1 runs (`command: ["./scripts/start.sh"]`). It also
# used to omit roles:seed_predefined while still calling
# signup:seed_organization, so on a fresh database with LAGO_CREATE_ORG=true it
# died on the roles.code NOT NULL constraint.
BOOTSTRAP_DB="${BOOTSTRAP_DB:-lago_bootstrap}"
base_url="${DATABASE_URL%%\?*}" # drop any query string before swapping the db name
bootstrap_url="${base_url%/*}/${BOOTSTRAP_DB}"

# Free the API port first. Under the default host networking every container
# shares the runner's network namespace, so the Puma this section boots would
# collide with the one still running from the section above.
docker stop lago-boot-api >/dev/null 2>&1 || true

# start.sh migrates but does not create — only migrate.sh carries the db:create
# fallback — so stand the empty database up first, as an operator would.
create_status=$(run_bounded lago-boot-createdb --network "$NET" \
  "${docker_env[@]}" -e "DATABASE_URL=$bootstrap_url" "$IMAGE" \
  bundle exec rails db:create)
if [ "$create_status" != "0" ]; then
  fail "could not create the empty bootstrap database (exit $create_status)"
  docker logs lago-boot-createdb 2>&1 | tail -20
fi

cleanup_containers+=("lago-boot-default")
docker run -d --name lago-boot-default --network "$NET" \
  "${docker_env[@]}" -e "DATABASE_URL=$bootstrap_url" "$IMAGE" >/dev/null

if wait_healthy lago-boot-default "http://localhost:${API_PORT}/health"; then
  pass "\`docker run $IMAGE\` migrates an empty database and boots the API"
else
  fail "default CMD did not bootstrap an empty database into a healthy API"
  docker logs lago-boot-default 2>&1 | tail -40
fi

bootstrap_roles=$(docker logs lago-boot-default 2>&1 | grep -c "NotNullViolation" || true)
if [ "$bootstrap_roles" = "0" ]; then
  pass "start.sh seeded roles before the organization"
else
  fail "start.sh hit a NOT NULL violation while seeding — roles:seed_predefined must run before signup:seed_organization"
fi

# --------------------------------------------------------------------------
if [ "$failures" -gt 0 ]; then
  printf '\n\033[31m%d boot-contract assertion(s) failed\033[0m\n' "$failures"
  exit 1
fi
printf '\n\033[32mboot contract holds\033[0m\n'
