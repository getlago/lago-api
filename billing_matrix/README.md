# billing matrix

A small, high-signal suite of billing scenarios that runs on a schedule, reports only what
changed since yesterday, and grows its own coverage as the billing code moves. It is not
RSpec and does not run in PR CI.

One **row** is one billing scenario: a setup, a dated timeline, and the few numbers that
matter. Rows are executed by a plain-Ruby runner that drives the real REST API, so
serializer and API defects stay in range.

## Run it

```bash
docker compose -f docker-compose.dev.yml exec -w /app/.worktrees/billing-matrix \
  -e RAILS_ENV=test \
  -e DATABASE_TEST_URL=postgresql://lago:changeme@db:5432/lago_matrix_test \
  -e GIT_SHA="$(git rev-parse HEAD)" \
  api bundle exec ruby billing_matrix/run.rb
```

Run from `lago/`, not from the worktree — that is where the compose file lives.

`--id ID` runs one row, `--area AREA` one area. Results land in
`tmp/billing_matrix/results.json`.

`--shard 1/4` runs a quarter of the rows, and **each shard needs its own database**. Teardown
deletes every row and takes exclusive locks across all 143 tables, so two shards sharing a
database corrupt each other's worlds instead of failing. `run.rb` enforces this: a shard only
runs against a database named `…_<index>_test`, e.g. `lago_matrix_1_test`. The index sits
before the suffix because `boot!` separately refuses any database not ending in `_test`.

`GIT_SHA` has to be passed in. Inside the container `.git` is a submodule gitlink pointing
outside the mounted volume, so `git rev-parse` finds nothing there.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | The suite ran and its assertions are provably alive — whatever the rows said |
| 2 | A canary passed. The run proves nothing; fix the assertion mechanism |
| 3 | The harness could not run at all |

Row failures do **not** produce a non-zero exit. Whether a failure is news is the ledger's
job, not the runner's.

## First-time database setup

The matrix has its own database. Do not point it at `lago_test`, which belongs to whatever
branch is checked out in the main working copy.

```bash
docker compose -f docker-compose.dev.yml exec -w /app/.worktrees/billing-matrix \
  -e RAILS_ENV=test \
  -e DATABASE_TEST_URL=postgresql://lago:changeme@db:5432/lago_matrix_test \
  api bundle exec rails db:create db:schema:load:primary
```

Omit `LAGO_DISABLE_SCHEMA_DUMP` here — it sets `schema_dump: false`, and then
`db:schema:load` loads nothing and silently leaves you with an empty database.

`config/keys/` is gitignored per checkout and Rails aborts without it, so copy the pair
from the main working copy, or run `scripts/generate.rsa.sh`.

One trap if you write a scratch script: do not put the app root on `$LOAD_PATH`. Karafka's
boot file is `karafka.rb` at the app root, so `require "karafka"` then resolves to it instead
of the gem and Rails dies with `uninitialized constant Karafka`. Require the runner by
absolute path.

## Layout

```
run.rb              entrypoint
runner/             the execution layer — see runner/CONTRACT.md for the interfaces
rows/               scenario rows, one file per area
canaries/           rows engineered to fail, one per assertion mechanism
salvage/            lifted from the old golden-billing-harness; deleted as it is ported
```

## The two rules that matter

**A row must be able to fail.** The previous suite's worst outcome was not a missed bug, it
was 26 rows reporting green while asserting nothing, for weeks, because an `ensure`/`throw`
swallowed every assertion. Hence `canaries/`: each one asserts something deliberately false,
so its failure proves a mechanism still works. One canary passing voids the whole run.

**Derive the expectation, then run.** Read the service, work out the number, write it down
with the `math:` that justifies it — and only then execute. If the two disagree, the default
conclusion is that the code is wrong, not the row. An expectation copied from observed
output documents a bug instead of catching it.

## The daily run and the ledger

`.github/workflows/billing-matrix-daily.yml` runs the whole suite every morning against a
fresh `lago_matrix_test`, then hands `results.json` to `billing_matrix/ledger.rb`, which
diffs today's verdicts against `ledger.yml` and reports only what changed — a row that went
red, a pinned finding that went green, a canary that stopped failing.

The ledger is never committed to `main` by the workflow. Changes are pushed to the
`billing-matrix/ledger` branch and opened as a pull request, amended in place while it
stays open, so a status change is reviewed before it becomes the record.

Nothing reaches Slack until two repository secrets exist: `SLACK_BOT_TOKEN` (a bot token
with `chat:write`) and `SLACK_DM_USER_ID` (the channel or user id the report is posted to).
Without them the suite still runs and the PR still opens, but the daily report and the
exit-2 / exit-3 alarms are silent — check the Actions log, not your DMs. `workflow_dispatch`
with `dry_run: true` runs everything and prints the report without committing, opening a
PR, or posting.

## Known issues

**One unreproduced flake.** During Phase 0, a single run saw
`organization.api_keys.first` return nil in a row that followed a row which raised
partway through `World.build!`. It has not recurred in any later run, including a
deliberate replay of the same failure sequence. The plausible mechanism is that `ApiKey`
carries `default_scope { active }`, keyed on `expires_at > Time.current`, so a leaked time
offset would hide every key — but no `travel_to` had run at that point, so that does not
fully explain it. `Context.isolate` was subsequently changed to run `enter` inside the
`ensure`, which closes one leak path.

Treat any recurrence as a harness defect, not a billing one, and chase it before adding
rows: the previous suite's credibility died of exactly this — intermittent failures nobody
could attribute, so failures stopped being read at all.

**Premium is forced on for every row.** `Context#enter` sets `License.premium? == true`
unconditionally. Features that silently no-op without a premium licence are a documented
source of missed findings in the old suite, and with premium always on that entire class is
invisible. Premium belongs on an axis, not in the harness — a Phase 1 change.

**Clickhouse is neither cleaned nor stubbed.** Organizations with `clickhouse_events_store`
are out of scope until a row needs them.
