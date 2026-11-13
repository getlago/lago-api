# Runner contract

Frozen interfaces. Three parts are built independently against this document; anything
here that turns out to be wrong gets changed **here first**, then in the code.

Everything lives in `module BillingMatrix`. No RSpec, anywhere. `require` by relative
path — there is no autoloader for this directory.

## How it runs

```
docker compose -f docker-compose.dev.yml exec -w /app/.worktrees/billing-matrix \
  -e RAILS_ENV=test \
  -e DATABASE_TEST_URL=postgresql://lago:changeme@db:5432/lago_matrix_test \
  -e GIT_SHA="$(git rev-parse HEAD)" \
  api bundle exec ruby billing_matrix/run.rb [--rows PATH] [--id ID] [--shard n/total]
```

**Shards must not share a database.** Teardown uses the deletion strategy, which takes
exclusive locks across all 143 tables and deletes whatever else is present, so two shards on
one database corrupt each other's worlds instead of failing — measured live as a foreign
organization appearing inside a clean `isolate`, plus 6–47s lock stalls against a 49ms
baseline. `run.rb` refuses to run `--shard n/total` unless the database name ends in `_n_test`. The
index sits *before* the suffix because `boot!` separately refuses any database whose name
does not end in `_test` — it deletes every row, so that guard stays. Shard databases are
therefore `lago_matrix_1_test`, `lago_matrix_2_test`, … and the unsharded one is
`lago_matrix_test`.

`GIT_SHA` has to be passed in: inside the container `.git` is a submodule gitlink pointing
at a path outside the mounted volume, so `git rev-parse` cannot resolve anything there and
`results.json` would carry a null revision.

Proven working: Rails 8.0.5.1 boots from this worktree, `lago_matrix_test` has 143 tables
and no pending migrations, `config/keys/` is populated. Do not use `lago_test` — it belongs
to another branch's checkout.

## Files and owners

| File | Provides |
| --- | --- |
| `errors.rb` | `Error`, `InvalidRow`, `Unsupported` — required first by every other file |
| `boot.rb` | `BillingMatrix.boot!` |
| `context.rb` | `BillingMatrix::Context` |
| `row.rb` | `BillingMatrix::Row` |
| `world.rb` | `BillingMatrix::World` |
| `timeline.rb` | `BillingMatrix::Timeline` |
| `observe.rb` | `BillingMatrix::Observe` |
| `comparison.rb` | `BillingMatrix::Comparison` |
| `results.rb` | `BillingMatrix::Results` |
| `../run.rb` | entrypoint, wires the above |

## boot.rb

`BillingMatrix.boot!(shard: nil)` — idempotent, safe to call twice, returns `nil`.
When a shard is supplied, validate its database pairing after loading the Rails environment
and before any cleanup, including on repeated calls. A mismatch raises `BillingMatrix::Error`.

Must, in this order: set `ENV["RAILS_ENV"] = "test"`; `require` the app's
`config/environment`; require `spec/support/monkey_patches/*.rb`; require and configure
`webmock` (`WebMock.enable!`, `WebMock.disable_net_connect!`), `sidekiq/testing`
(`Sidekiq::Testing.fake!`), `factory_bot` (`FactoryBot.reload`, **not**
`find_definitions` — factory_bot_rails' railtie already ran that during
`config/environment`, and a second call raises `DuplicateDefinitionError`),
`database_cleaner-active_record` (`DatabaseCleaner.allow_remote_database_url = true`),
`ActiveJob::Uniqueness.test_mode!`.

Must abort with a clear message if `Rails.env` is not `test`, or if the database name does
not end in `_test`. It runs `DatabaseCleaner.clean_with(:deletion)` — a wrong database is
data loss.

It must **not** require `rspec`, `rails_helper`, or `spec/spec_helper`, and must not load
`spec/support/**` wholesale — only `monkey_patches`. The support helpers are mixed into
`Context` explicitly.

## context.rb

One `Context` instance is one isolated row execution.

```ruby
BillingMatrix::Context.isolate do |ctx|   # yields a prepared Context, returns the block's value
  # ...
end
```

On entry the block is guaranteed: an empty database, empty ActiveJob and Sidekiq queues,
HTTP blocked except a stubbed PDF service, `License.premium?` equal to the `premium:` keyword
(default `true`), and real time. On exit, guaranteed regardless of how the block ended:
database cleaned, time restored, WebMock reset, queues cleared, `License.premium? == false`.

`License` is one process-global `LagoUtils::License` instance, so the licence is row state,
not harness state: `ctx.premium = false` / `ctx.premium?` are the only way to touch it, and
`leave` drops it unconditionally so a row cannot leak premium into the next. `World` calls
`ctx.premium=` from the row's `setup.premium` (see below), because `run.rb` does not yet pass
the keyword.

`enter` must run **inside** the `begin` that `ensure`s `leave`. `enter` mutates global
state — premium flag, WebMock stubs, the time offset — so an `enter` that raises halfway
leaks all of it into the next row unless `leave` still runs. Teardown must also survive a
failing step: run every teardown action and re-raise the first error afterwards, rather
than letting the first one skip the rest.

`Context` includes, in an order where `QueuesHelper#enqueued_jobs` can still `super()` into
`ActiveJob::TestHelper#enqueued_jobs`:

```
FactoryBot::Syntax::Methods
ActiveSupport::Testing::TimeHelpers
ActiveJob::TestHelper
ActionDispatch::Integration::Runner   # supplies get/post/put/delete + response
WebMock::API
ApiHelper  QueuesHelper  ScenariosHelper  PdfHelper  LicenseHelper
```

Two things `ActionDispatch::Integration::Runner` needs and RSpec normally supplies:
`app` (return `Rails.application`) and per-row `reset!` of the integration session.

The `before_setup` / `after_teardown` chains need a terminal. `Runner#before_setup` calls
`super`, through `ActiveJob::TestHelper` and `TimeHelpers`, and `Minitest::Test` normally
ends the chain; without it the chain dies with `NoMethodError`. `Context` therefore includes
a `Lifecycle` module of no-ops **first**, so it sits last in the ancestor chain.

Requiring `context.rb` boots Rails, because the `include` lines need those constants at load
time. `run.rb` calling `boot!` afterwards is a no-op.

`ScenariosHelper` was written against RSpec `let`s and calls nine reader methods that do
not exist here. `Context` must expose all nine as `attr_accessor`, defaulting to `nil`,
for `World` to populate:

```
organization  customer  plan  subscription  billable_metric  billing_entity
tax  coupon  wallet
```

One method in `ScenariosHelper` — `mock_vies_check!` at line 307, with a bang — uses
`instance_double` and `allow`. Do not try to support it; override it in the `Context` class
body (a method defined on the class always beats an included module) and raise
`BillingMatrix::Unsupported`. Nothing else in that file touches RSpec.

`Context` also exposes `#travel_to_and_run(iso8601_string) { ... }`, wrapping
`TimeHelpers#travel_to` with a parsed `DateTime`, since every timeline step is dated.

## row.rb

```ruby
rows = BillingMatrix::Row.load_all("billing_matrix/rows")   # => [Row, ...]
row  = BillingMatrix::Row.new(hash, source: path)
row.id      # String, unique across all files, "area/axis-value/axis-value"
row.area    # String
row.axes    # Hash{String=>String} — the cell this row claims
row.setup   # Hash
row.timeline # Array<Hash> — each has "at" and "do"
row.expect   # Hash
row.math     # String or nil
row.control  # String (another row's id) or nil
row.canary   # Hash or nil — presence means this row is expected to FAIL
row.pins     # Array<String> — finding ids (F69, BIL-537) this row pins; [] by default
row.validate! # raises BillingMatrix::InvalidRow with a message naming id + source + field

BillingMatrix::Row.reject_duplicate_ids!(rows)  # class method, raises InvalidRow naming both
                                             # sources on a collision
```

`load_all` accepts a file, a directory, or an array of paths. The entrypoint passes all
repeated `--rows` arguments together. It validates each row, then checks duplicate IDs and
control references across the combined corpus, so controls can live in another input path.

Validation rules, all of which must fail loudly rather than be tolerated:

- `id`, `area`, `timeline`, `expect` are required; `id` unique across the whole load
- every timeline step has a parseable `at` and a `do` naming a verb `Timeline` implements
- `at` values are non-decreasing down the list
- `math` is required whenever any expected value is a non-zero `*_cents`
- a row whose `expect` asserts an interaction must name a `control`
- reject a timeline that produces a billed period from **exactly one** `ingest_events`
  step with `count: 1`, unless the row sets `single_event_is_the_point: true` — one event
  cannot distinguish per-event pricing from a cumulative delta, and rows like that passed
  for a year in the old suite while asserting nothing
- `pins`, when present, is a list of finding ids (`F69`, `BIL-537`); a canary cannot pin
  anything. The ledger uses it to name the finding a red row stands for

A row **asserts the correct value, never the observed one.** A row that pins a finding is
expected to be red until Lago is fixed; its `math:` says what Lago does instead and why that
is wrong. Its `control` is a row on which the same machinery is correct.

Keep the schema small. Use the supported keys in `row.rb` and the execution helpers
as the vocabulary; the previous harness is linked from the README for historical reference.

## world.rb

```ruby
BillingMatrix::World.build!(ctx, row.setup)   # populates ctx's nine accessors, returns nil
```

**Pass a Hash literal, never bare keywords.** Every `ScenariosHelper` method is
`def create_metric(params, **kwargs)`, so Ruby 3 routes `create_metric(name: "x")` into
`**kwargs` and raises `ArgumentError: wrong number of arguments (given 0, expected 1)`.
It must be `create_metric({name: "x", code: "x"})`. This applies to `Timeline` too.

`World` must create the organization and assign `ctx.organization` **before any API call** —
`ApiHelper#set_headers` reads `organization.api_keys.first`, so a nil organization surfaces
as a bare `NoMethodError` from `api_helper.rb:41` with nothing pointing at the real cause.

Builds setup through the **REST API** via `ScenariosHelper` wherever an endpoint exists, so
serializer and API-contract defects stay in range; FactoryBot only for what the API cannot
express (start with `organization` and its billing entity). Set `premium_integrations` on
the organization when the setup asks for a premium feature — the old suite lost findings to
features silently dropping without it.

Supported `setup` keys for the MVP, all optional: `premium`, `organization`, `billing_entity`,
`taxes`, `metrics`, `plan`, `charges`, `fixed_charges`, `thresholds`, `customer`,
`coupons`, `wallets`, `add_ons`, `plans`. Unknown key ⇒ raise `BillingMatrix::InvalidRow`.

### `premium`

`setup.premium: false` runs the row without a premium licence; `true` (the default when the
key is absent) is what every pre-existing row means. It must be a boolean. It is a first-class
axis — plan overrides, usage thresholds, minimum commitments and progressive billing all
answer 200 and silently no-op without a licence (`Plans::CreateService:82`,
`Plans::UpdateService:75,79`, `Plans::OverrideService:57,64`), and the previous suite never saw
that class of defect because premium was hardcoded on. Rules `World` enforces:

- `premium: false` with `organization.premium_integrations` present is `InvalidRow`: every
  premium integration is also gated on `License.premium?`, so the row would test nothing.
- Implied integrations (`thresholds` ⇒ `progressive_billing`, `PREMIUM_FEATURE_OF`) are added
  only under a premium licence; a row that turned the licence off is asking to see the feature
  no-op, not to be rescued by a setup key.
- The "plan has no minimum commitment" guard in `verify_plan!` fires only under a premium
  licence; without one the dropped commitment is the behaviour under test and `expect` must
  state the shorter invoice. `expect_count!` for charges/thresholds is unchanged: asking for
  thresholds without a licence still errors, because the plan cannot carry them at all.
- Every `premium: false` row names a `premium: true` row (same setup, same timeline) as its
  `control:`, and the two assert different figures — an axis whose values cannot be shown to
  produce different results is a label, not coverage. `billing_matrix/rows/premium_gating.yml`
  is the reference pair.

`plans` is a list of **extra** plans, each `{code, ...plan keys, charges: [...], thresholds: [...]}`
with the same entry shapes as the top-level sections, so a timeline can move the subscription
onto one (an upgrade is `create_subscription` with the same `external_id` and the other
`plan_code`). `ctx.plan` stays the primary plan, so `update_plan` / `update_charge` keep
targeting it. An extra plan's code must differ from the primary's.

A fixed charge's `code` defaults to its add-on code: the subscription fixed-charge endpoint
addresses fixed charges by `code`, which the API otherwise leaves nil.

## timeline.rb

```ruby
BillingMatrix::Timeline.run!(ctx, row.timeline)   # returns nil
BillingMatrix::Timeline.verbs                     # => [String] — Row validates against this
```

Each step runs inside `ctx.travel_to_and_run(step["at"])`. **Steps must be sequential, never
nested** — Rails ≥ 7.1 raises if block-form `travel_to` is called inside another block-form
`travel_to`. Keep the verb set small and use `spec/support/scenarios_helper.rb` for the
current helper interfaces:

```
create_subscription   update_subscription   terminate_subscription
ingest_events         perform_usage_update  perform_billing
refresh_invoice       finalize_invoice      void_invoice
top_up_wallet         create_credit_note    preview_invoice
update_plan           update_charge         update_customer
update_fixed_charge   delete_metric
```

Selectors: `invoice:` (`first`, `last`, or `{invoice_type:, status:, index:}` with a 0-based
`index`, default last), `wallet: <code>`, `charge: <code>`, `fixed_charge: <code>`,
`metric: <code>` — each optional when exactly one candidate exists.

`update_fixed_charge` is `PUT /subscriptions/:external_id/fixed_charges/:code` (body keys
`units`, `apply_units_immediately`, `properties`, `invoice_display_name`, `tax_codes`), the
subscription-level endpoint that decides between a units-only override and a plan clone.
`delete_metric` is `DELETE /billable_metrics/:code`.

An unknown verb raises `BillingMatrix::Unsupported` naming the verb. Never silently skip a
step — a dropped step is a false green.

## observe.rb

```ruby
BillingMatrix::Observe.call(ctx, row.expect)   # => Hash, same shape as row.expect
```

Reads back only the keys the row actually asserts, as plain Ruby (no AR objects), so
`Comparison` is a pure function of two hashes. Volatile fields — ids, invoice numbers,
timestamps not under test — must not appear in the output at all.

Supported `expect` keys for the MVP: `invoices` (a count), `invoice` (single, when exactly
one exists), `invoice[N]` (1-indexed, chronological), `wallet`, `credit_note`, `subscription`,
`preview`, `error`. Inside an invoice: `invoice_type`, `status`, `fees_amount_cents`,
`coupons_amount_cents`, `prepaid_credit_amount_cents`,
`progressive_billing_credit_amount_cents`, `credit_notes_amount_cents`,
`sub_total_excluding_taxes_amount_cents`, `taxes_amount_cents`, `total_amount_cents`,
`fees_count`, and `fees` as a list. `credit_note` (the customer's single credit note) and
`wallet` accept any reader on the model, e.g. `credit_amount_cents`, `balance_amount_cents`,
`credit_status`, `balance_cents`.

`subscription` reads `ctx.subscription` after the timeline: `plan_overridden` (boolean — true when
the current plan has a `parent_id`, which is what `Plans::OverrideService` leaves behind),
`plan_name`, `plan_code`, or any reader on the model (`status`, `billing_time`). Never assert
`plan_id`: an override creates a fresh UUID no row can state; `plan_overridden` is the same fact,
deterministically. A row on a plan-override axis asserts it on both the churn row and its
control, otherwise an override the API accepted but ignored is indistinguishable from one that
worked.

## comparison.rb

```ruby
BillingMatrix::Comparison.call(expected:, observed:)   # => Result
result.match?        # true / false
result.mismatches    # => [{path:, expected:, observed:}]
```

Keep comparison independent of RSpec matchers: `*_cents` compared as exact integers, `units` / `precise_unit_amount` /
`taxes_rate` as `BigDecimal`, dates parsed before comparison, and fees matched by content
identity (`fee_type`, `item_code`, `item_type`, `from_date`, `to_date`) rather than by
array order.

Two corrections to carry — both were findings against the old harness:

- fee identity keys could not disambiguate real fee pairs, so rows quietly degraded to
  asserting only `fees_count` and `fees_amount_cents`. When two observed fees collide on
  the identity keys, that is a `Comparison` **error**, not a fallback.
- a `0¢` subscription fee is a real fee and must be listed. Do not special-case it away.

A key present in `expected` and absent in `observed` is a mismatch, never a skip.

## results.rb

```ruby
r = BillingMatrix::Results.new
r.record(row:, verdict:, mismatches: [], error: nil, duration_ms:)
r.write!("tmp/billing_matrix/results.json")
r.verdict_for(id)  # the verdict AS RECORDED, i.e. after canary semantics
r.summary   # => {passed: n, failed: n, errored: n, canaries_broken: n}
```

**`Results` owns the canary flip, and it is applied in exactly one place.** `record` takes
the verdict a row would get if it were ordinary — `:passed`/`:failed` off a `Comparison`,
`:errored` off an exception — and flips it itself for a canary row. Callers must not
pre-flip: doing it in both the entrypoint and here turns every healthy canary into
`:canary_broken` and voids every run. The entrypoint logs `verdict_for` precisely so it
displays what was recorded rather than what it passed in.

`verdict` is one of `:passed`, `:failed`, `:errored`, `:canary_broken`. A canary row that
*passes* is `:canary_broken` — and one broken canary voids the whole run, because the
mechanism it guards is no longer proven.

`results.json`, consumed later by the ledger diff and the Slack report:

```json
{
  "run": {"started_at": "...", "finished_at": "...", "revision": "<git sha>",
          "summary": {"passed": 0, "failed": 0, "errored": 0, "canaries_broken": 0}},
  "rows": [
    {"id": "...", "area": "...", "pins": ["F69"], "verdict": "failed", "duration_ms": 6912,
     "mismatches": [{"path": "invoice[1].taxes_amount_cents", "expected": 200, "observed": 1200}],
     "error": null}
  ]
}
```

Every result carries the row's `pins` (an empty list when unpinned). The ledger stores
these finding IDs and names them beside the row in text and Slack transition reports.
Transitions remain keyed by row ID: several rows can pin the same finding without hiding
one another's failures. Adding pins to a known failure updates its metadata silently;
older results without `pins` preserve any existing association. Errored rows never change
an existing ledger entry.

## Errors

Defined once, in `errors.rb`, which every other file requires. Do not redefine them
defensively per file.

```ruby
BillingMatrix::Error          # base
BillingMatrix::InvalidRow     # a row is malformed — names id, source, field
BillingMatrix::Unsupported    # the row asks for something the runner cannot do
BillingMatrix::Comparison::AmbiguousFeeIdentity   # two fees cannot be told apart
```

`Unsupported` is a first-class outcome, not a failure: it means the row is ahead of the
harness. It records as `:errored` and never as `:passed`.
