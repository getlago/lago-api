# Payments list filters: performance scripts

Reproducible tooling behind the performance analysis of the payments list
filters (`PaymentsQuery`, `GET /api/v1/payments`, GraphQL `payments`). Every
figure in the internal performance document comes from these scripts run on
the synthetic dataset they build. Nothing here reads or contains production
data; the skews in `generate.rb` are illustrative round numbers.

Development only. Run everything against a throwaway database whose name
contains `perf` (the generator refuses anything else).

## One-time setup

```sh
# a separate database in the dev PostgreSQL container
psql -U lago -d postgres -c "CREATE DATABASE lago_perf OWNER lago"
psql -U lago -d lago_perf -q -f db/structure.sql
```

Point every command below at it: `DATABASE_URL=postgresql://lago:changeme@db:5432/lago_perf`
(add `DIRECT_DATABASE_URL` and `EVENTS_DATABASE_URL` with the same value so no
role can reach the dev database).

## Scripts

| script | what it does | output |
|---|---|---|
| `phase0.sql` | read-only replica queries: scale, skew, write rate, index usage. Results are confidential and go only into the internal document. | terminal |
| `generate.rb` | builds the dataset: one big organization (default 5M payments), 50 smaller ones, matching invoices, payment requests, receipts, payment methods, providers. Deterministic (`PERF_SEED`). | row counts, sizes, `tmp/perf_payments_filters_credentials.json` (local API key) |
| `cases.rb` | the case matrix (control, each filter at a common and a rare value, hits and misses, combos, five-filter worst case, page 50). Values are resolved from the data. | library |
| `explain.rb` | runs each case through `PaymentsQuery` and captures `EXPLAIN (ANALYZE, BUFFERS)` for the list and for the `COUNT(*)` Kaminari issues, median of 3. | `plans/<phase>/<case>.txt`, `<case>.count.txt`, `summary.md/json` |
| `bench.rb` | 20 concurrent clients, 60 s per case, against `GET /api/v1/payments` (`PERF_MODE=http`) or the raw SQL through ActiveRecord (`PERF_MODE=sql`). | `bench/<phase>.<mode>.md/json` |
| `compare.rb` | before/after table and the G1-G9 scoreboard from two phases. | `compare/<before>_vs_<after>.md` |

## Reproduce

```sh
export DATABASE_URL=postgresql://lago:changeme@db:5432/lago_perf
bundle exec rails runner script/perf/payments_filters/generate.rb            # ~minutes, prints sizes
PERF_PHASE=baseline bundle exec rails runner script/perf/payments_filters/explain.rb
# start an API against the perf database, then:
PERF_PHASE=baseline PERF_API_URL=http://127.0.0.1:3000 bundle exec rails runner script/perf/payments_filters/bench.rb
PERF_PHASE=baseline PERF_MODE=sql bundle exec rails runner script/perf/payments_filters/bench.rb
# apply the index migrations and the query rewrites, then rerun with PERF_PHASE=after
ruby script/perf/payments_filters/compare.rb baseline after
```

Knobs: `PERF_BIG_PAYMENTS`, `PERF_SMALL_ORGS`, `PERF_BIG_CUSTOMERS`, `PERF_SEED`,
`PERF_MONTHS` (generator); `PERF_PHASE`, `PERF_ONLY` (regex on case names),
`PERF_RUNS`, `PERF_TIMEOUT` (explain); `PERF_CLIENTS`, `PERF_DURATION`,
`PERF_MODE`, `PERF_API_URL` (bench).

## Committed plans

`plans/baseline/` and `plans/after/` hold the plans captured on the synthetic
dataset with organization UUIDs redacted. They are evidence for the shape of
each plan (index used, Seq Scan, Sort); absolute timings depend on the machine.
