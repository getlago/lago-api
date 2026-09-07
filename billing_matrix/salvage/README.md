# salvage

Lifted verbatim from `golden-billing-harness` @ `8cd803568` (2026-08-31). Nothing here
is loaded by anything — the directory sits outside `spec/` on purpose, so `spec_helper`
does not autoload it and a half-ported file cannot break the suite.

Every file is either ported into `billing_matrix/` or deleted. When this directory is
empty, delete it.

## runner/

| File | Fate |
| --- | --- |
| `legality.rb` | Port. Derives axis domains from model constants and filters them with predicates that mirror the real validators. Drop the block vocabulary, keep the mechanism. |
| `comparison.rb` | Port close to as-is. Exact cents, BigDecimal for units and rates, parsed dates, fees matched on content keys, volatile fields absent from the schema. |
| `capabilities.rb` | Port. Derives the runner's capability list from its own source so the row schema and the executor cannot silently disagree. |
| `runner.rb` | Reference only, do not port. The 30 timeline verbs are the vocabulary the new runner needs; the RSpec coupling and the single-spec-file design are what we are replacing. |
| `schema.json` | Reference. Source for the new row schema, which will be much smaller. |

## rows/

The four blocks that produced findings, and the canaries.

| File | Fate |
| --- | --- |
| `b15_interactions.yml` | Mine for rows pinned in `state/findings.yml`. Becomes `rows/interactions.yml`. |
| `b17_stacks.yml` | Same. The full-stack row that exposed the progressive-billing tax defect lives here. |
| `b18_mid_flight.yml` | Mine. Becomes `rows/mid_flight.yml`. |
| `b20_identity_churn.yml` | Mine. Densest MONEY block — 12 findings. Becomes `rows/identity_churn.yml`. |
| `canaries.yml` | Trim to one canary per assertion mechanism the new runner actually has, then move to `canaries/`. |

Import rule: a row comes across only if it is named in a finding's `pins:`, or it is a
control for a row that is. Everything else stays behind.

## state/

| File | Fate |
| --- | --- |
| `blocks.yml` | Seed for `areas.yml`. Keep the three axis patterns that generated findings — reducer-pipeline pairs, identity churn as a join-key intersection, surface-where-it-can-differ. Drop the pricing grids. |
| `findings.yml` | Seed for `ledger.yml`. 75 findings; the 18 with a pinning row become entries with their original `noted` date as `first_seen`. |
| `leads.yml` | Seed for `leads.yml`. |
