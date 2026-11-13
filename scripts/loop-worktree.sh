#!/usr/bin/env bash
# loop-worktree.sh — an isolated lago-api worktree with its own container, for the loop pipeline.
#
# The worktree lives in <lago>/api-worktrees/<name> and is mounted in a container named
# lago_api_wt_<sanitized-name>, attached to the main dev stack network. It shares the dev
# stack's Postgres, Redis and ClickHouse, so rspec runs there exactly like in lago_api_dev.
# The container runs no server: it only hosts `docker exec` commands.
#
# Usage:
#   loop-worktree.sh create <branch> [--from=<base>]   base defaults to main
#   loop-worktree.sh restart <name>
#   loop-worktree.sh destroy <name>                    asks for confirmation
#   loop-worktree.sh container <name>                  prints the container name
#   loop-worktree.sh ps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
LAGO_PATH="$(cd "$API_PATH/.." && pwd)"
WORKTREE_DIR="$LAGO_PATH/api-worktrees"
COMPOSE_DIR="$WORKTREE_DIR/.compose"
DEV_CONTAINER="lago_api_dev"

sanitize() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g'; }
container_name() { echo "lago_api_wt_$(sanitize "$1")"; }
compose_file() { echo "$COMPOSE_DIR/$1.yml"; }

dev_env() {
  docker inspect "$DEV_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep "^$1=" | head -1 | cut -d= -f2-
}

write_compose() {
  local name="$1" wt_path="$2" container
  container="$(container_name "$name")"
  mkdir -p "$COMPOSE_DIR"

  cat >"$(compose_file "$name")" <<YAML
name: lago_wt_$(sanitize "$name")

services:
  api:
    image: api_dev
    pull_policy: never
    container_name: ${container}
    restart: unless-stopped
    command: bash -c "rm -f /tmp/loop-ready && bundle install && ./scripts/generate.rsa.sh && touch /tmp/loop-ready && sleep infinity"
    volumes:
      - ${wt_path}:/app:cached
    env_file:
      - path: ${LAGO_PATH}/.env.development.default
      - path: ${LAGO_PATH}/.env.development
        required: false
    environment:
      - DATABASE_TEST_URL=\${LOOP_WT_DATABASE_TEST_URL}
    networks:
      - lago_net

networks:
  lago_net:
    external: true
    name: lago_dev_default
YAML
}

wait_ready() {
  local container="$1"
  for _ in $(seq 1 120); do
    if docker exec "$container" test -f /tmp/loop-ready 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "Error: $container did not become ready within 4 minutes (docker logs $container)" >&2
  exit 1
}

start_container() {
  local name="$1" test_url
  test_url="$(dev_env DATABASE_TEST_URL)"
  if [[ -z "$test_url" ]]; then
    echo "Error: $DEV_CONTAINER is not running or has no DATABASE_TEST_URL" >&2
    exit 1
  fi
  LOOP_WT_DATABASE_TEST_URL="$test_url" docker compose -f "$(compose_file "$name")" up -d
  wait_ready "$(container_name "$name")"
}

cmd_create() {
  local branch="" base="main"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from=*) base="${1#--from=}"; shift ;;
      *) branch="$1"; shift ;;
    esac
  done
  [[ -z "$branch" ]] && { echo "usage: loop-worktree.sh create <branch> [--from=<base>]" >&2; exit 64; }

  local wt_path="$WORKTREE_DIR/$branch"
  [[ -e "$wt_path" ]] && { echo "Error: $wt_path already exists" >&2; exit 1; }
  if git -C "$API_PATH" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    echo "Error: branch '$branch' already exists in $API_PATH" >&2
    exit 1
  fi

  mkdir -p "$WORKTREE_DIR"
  git -C "$API_PATH" worktree prune
  git -C "$API_PATH" worktree add -b "$branch" "$wt_path" "$base"

  if [[ -d "$API_PATH/config/keys" ]]; then
    mkdir -p "$wt_path/config/keys"
    cp -R "$API_PATH/config/keys/." "$wt_path/config/keys/"
  fi

  write_compose "$branch" "$wt_path"
  start_container "$branch"

  echo "worktree: $wt_path"
  echo "branch: $branch"
  echo "container: $(container_name "$branch")"
}

cmd_restart() {
  local name="${1:?usage: loop-worktree.sh restart <name>}"
  [[ -f "$(compose_file "$name")" ]] || { echo "Error: no worktree container for '$name'" >&2; exit 1; }
  docker restart "$(container_name "$name")" >/dev/null
  wait_ready "$(container_name "$name")"
  echo "restarted: $(container_name "$name")"
}

cmd_destroy() {
  local name="${1:?usage: loop-worktree.sh destroy <name>}"
  local wt_path="$WORKTREE_DIR/$name"

  echo "This removes the container $(container_name "$name"), the worktree $wt_path and the local branch $name."
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "aborted"; exit 1; }

  if [[ -f "$(compose_file "$name")" ]]; then
    LOOP_WT_DATABASE_TEST_URL="" docker compose -f "$(compose_file "$name")" down
    rm -f "$(compose_file "$name")"
  fi

  if [[ -d "$wt_path" ]]; then
    git -C "$API_PATH" worktree remove "$wt_path"
  fi
  git -C "$API_PATH" worktree prune
  git -C "$API_PATH" branch -D "$name" 2>/dev/null || true
  echo "destroyed: $name"
}

cmd_ps() {
  docker ps -a --filter "name=lago_api_wt_" --format 'table {{.Names}}\t{{.Status}}'
}

case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  restart) shift; cmd_restart "$@" ;;
  destroy) shift; cmd_destroy "$@" ;;
  container) shift; container_name "${1:?usage: loop-worktree.sh container <name>}" ;;
  ps) cmd_ps ;;
  *)
    echo "usage: loop-worktree.sh create <branch> [--from=<base>] | restart <name> | destroy <name> | container <name> | ps" >&2
    exit 64
    ;;
esac
