#!/usr/bin/env bash
# iter-budget.sh — attempt budget for any skill that retries.
#
# The cap lives here, in the filesystem, not in the agent's memory of how many
# times it has already tried. Every retry has to charge the budget through this
# script, and the script is what refuses the attempt past the cap.
#
# Nothing here is specific to one pipeline: a "counter" is just a filename, so
# any skill can own one by picking a name.
#
# Usage:
#   iter-budget.sh <ISSUE-ID> <counter>          charge one attempt; prints "N/MAX"
#                                                exit 0 = proceed
#                                                exit 1 = budget exhausted, stop and escalate
#   iter-budget.sh <ISSUE-ID> reset [<counter>]  reset one counter, or all of them
#   iter-budget.sh <ISSUE-ID> show               print every counter for this issue
#
# Counters in use: review (build↔review cycles in loop-run), ci (CI fix cycles in
# loop-run), ci-revise (CI fix cycles in loop-revise), triage-review (analysis
# review cycles in triage-frontend-ticket, capped at 2).
#
# Configuration:
#   ITER_MAX               attempts allowed per counter (default 3)
#   ITER_MAX_<COUNTER>     per-counter override, counter upper-cased with hyphens
#                          as underscores (e.g. ITER_MAX_TRIAGE_REVIEW). Wins over
#                          ITER_MAX and over built-in caps.
#   ITER_STATE_DIR         where counters live (default ~/.claude/loop-state — the path is
#                          historical; the loop pipeline keeps its own artifacts there too,
#                          but nothing in this script depends on that)
#
#   LOOP_MAX_ITER, LOOP_MAX_ITER_<COUNTER> and LOOP_STATE_DIR are honoured as
#   deprecated aliases, so an existing shell profile keeps working.
set -euo pipefail

ISSUE="${1:-}"
CMD="${2:-}"
if [ -z "$ISSUE" ] || [ -z "$CMD" ]; then
  echo "usage: iter-budget.sh <ISSUE-ID> <counter>|reset [<counter>]|show" >&2
  exit 64
fi

STATE_ROOT="${ITER_STATE_DIR:-${LOOP_STATE_DIR:-$HOME/.claude/loop-state}}"
DIR="$STATE_ROOT/$ISSUE/counters"

# Cap for one counter. An explicit per-counter override always wins; otherwise
# counters with a built-in cap use it, and everything else falls back to the
# global default. Built-in caps are deliberately independent of that default: a
# counter whose budget is part of a documented contract must not silently widen
# because the global default was raised.
counter_max() {
  local counter="$1" suffix override legacy
  suffix="$(printf '%s' "$counter" | tr '[:lower:]-' '[:upper:]_')"
  override="ITER_MAX_$suffix"
  legacy="LOOP_MAX_ITER_$suffix"

  if [ -n "${!override:-}" ]; then
    echo "${!override}"
    return
  fi

  if [ -n "${!legacy:-}" ]; then
    echo "${!legacy}"
    return
  fi

  case "$counter" in
    triage-review) echo 2 ;;
    *) echo "${ITER_MAX:-${LOOP_MAX_ITER:-3}}" ;;
  esac
}

mkdir -p "$DIR"

case "$CMD" in
  reset)
    if [ -n "${3:-}" ]; then rm -f "$DIR/$3"; else rm -f "$DIR"/*; fi
    echo "reset"
    ;;
  show)
    found=0
    for f in "$DIR"/*; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"
      echo "$name=$(cat "$f")/$(counter_max "$name")"
      found=1
    done
    if [ "$found" -eq 0 ]; then echo "no counters yet"; fi
    ;;
  *)
    FILE="$DIR/$CMD"
    MAX="$(counter_max "$CMD")"
    N=$(( $(cat "$FILE" 2>/dev/null || echo 0) + 1 ))
    echo "$N" >"$FILE"
    echo "$N/$MAX"
    if [ "$N" -gt "$MAX" ]; then
      exit 1
    fi
    exit 0
    ;;
esac
