#!/bin/bash
set -euo pipefail

# Runs a golden-suite command in whichever context this machine offers, so the skill and the five
# agent definitions can carry ONE command string instead of a host form and a CI form that drift.
#
#   dev/golden/run.sh rspec spec/scenarios/golden
#   dev/golden/run.sh rspec spec/scenarios/golden -e "b01/volume"
#   dev/golden/run.sh rake golden:ledger
#   dev/golden/run.sh ruby dev/golden/parallel.rb
#
# Three contexts, detected in this order:
#
#   inside the api container   /.dockerenv exists; bundle is already on PATH
#   a CI runner                $CI is set. spec.yml installs ruby natively and runs postgres and
#                              redis as service containers, so there is no api container to enter
#   a developer's host         neither of the above; re-enter through docker
#
# The container is addressed by name rather than through `lago exec`, because `lago` is a shell
# alias and aliases do not exist inside a script. GOLDEN_CONTAINER overrides the name;
# GOLDEN_EXEC=native|container overrides the detection entirely.

if [ $# -eq 0 ]; then
  echo "usage: dev/golden/run.sh <command> [args...]   e.g. dev/golden/run.sh rake golden:ledger" >&2
  exit 64
fi

container="${GOLDEN_CONTAINER:-lago_api_dev}"
target="${GOLDEN_EXEC:-}"

if [ -z "$target" ]; then
  if [ -f /.dockerenv ] || [ -n "${CI:-}" ]; then
    target=native
  else
    target=container
  fi
fi

if [ "$target" = native ]; then
  exec env LAGO_DISABLE_SCHEMA_DUMP=true bundle exec "$@"
fi

if ! docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
  echo "dev/golden/run.sh: container '$container' is not running." >&2
  echo "Start the stack first, or set GOLDEN_EXEC=native to run against a local ruby." >&2
  exit 69
fi

# A TTY gives rspec its progress dots and colour when a human is watching, and breaks the run when
# stdout is a pipe or a CI log. Held as a string rather than an array because bash 3.2 — which is
# what /bin/bash still is on macOS — treats an empty array expansion as unset under `set -u`.
tty=""
if [ -t 0 ] && [ -t 1 ]; then
  tty="-t"
fi

exec docker exec -i $tty -w /app -e LAGO_DISABLE_SCHEMA_DUMP=true "$container" bundle exec "$@"
