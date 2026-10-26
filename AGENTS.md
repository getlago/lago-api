# AGENTS.md

Rails backend of [Lago](https://github.com/getlago/lago). PostgreSQL and Redis are required; ClickHouse, Kafka and a premium license are optional, so code must also work without them.

This repository is public. Code, comments, specs, commits and PRs must not contain customer data, secrets or internal URLs, and ticket IDs stay out of code and comments.

## Commands

The app runs with Docker Compose from [getlago/lago](https://github.com/getlago/lago), where `lago` is an alias for `docker compose -f docker-compose.dev.yml` (see its `docs/dev_environment.md`). Run commands in the `api` service. Specs use the `lago_test` database through `DATABASE_TEST_URL`, which only the `api` service sets. In a worker container the test environment falls back to `DATABASE_URL`, the development database `lago`, and the suite empties it.

| Task | Command |
|---|---|
| Run specs | `lago exec api bundle exec rspec spec/path/to_spec.rb:42` |
| Lint | `lago exec api bundle exec rubocop -a <changed files>` |
| Create a migration | `lago exec api bin/rails g migration AddStatusToContracts` |
| Migrate PostgreSQL and ClickHouse | `lago exec api bin/rails db:migrate` |
| Dump `schema.graphql` and `schema.json` | `lago exec api bin/rails graphql:schema:dump` |
| Refresh model annotations | `lago exec api bundle exec annotaterb models` |
| Normalize locale files | `lago exec api bundle exec i18n-tasks normalize` |

Before finishing a change:

- The specs that cover it pass, and only those run (see "Specs" for what counts as a passing run). CI runs the full suite, lints the changed `.rb` files and runs `bin/rails zeitwerk:check`.
- `rubocop -a` passes on the changed files.
- The generated files below are regenerated.
- A convention the change adds, or a rule of this file it makes wrong, is updated here in the same PR.

Running commands:

- The container mounts the main checkout at `/app`. For a git worktree inside it, add `-w /app/<worktree path>` after `exec`. The worktree also needs the gitignored `.env`, `config/master.key` and `config/keys` of the main checkout: link them with relative symlinks so they resolve inside the container (`config/keys` sits one level deeper than `.env`, so its target has one more `../`). Create the symlinks from the container: one created or changed on the host can keep its old target inside it. Worktrees share the databases of the main checkout, so check `bin/rails db:migrate:status` before migrating: migrations applied from other branches end up in the `db/structure.sql` dump. When the worktree's `Gemfile.lock` differs from the main checkout's, run `bundle install` from the worktree first: the container's gems follow the main checkout.
- Specs run from a worktree take `LAGO_DISABLE_SCHEMA_DUMP=true ANNOTATERB_SKIP_ON_DB_TASKS=true`. When the branch's schema differs from `lago_test`, the suite reloads the test database, and without these variables it also rewrites `db/structure.sql` and the model annotations of the worktree. When another run holds `lago_test` (lock waits in `pg_stat_activity`), point `DATABASE_TEST_URL` at a throwaway `lago_test_<name>` database, prepare it with `RAILS_ENV=test bin/rails db:create:primary db:schema:load:primary`, run the specs, then `RAILS_ENV=test bin/rails db:drop:primary`. Load the schema without `LAGO_DISABLE_SCHEMA_DUMP`: the test config reads `schema_dump` for the load too, so the variable turns the load into a no-op.
- Without Docker, the same commands run without the `lago exec api` prefix. `config/environments/test.rb` loads `.env`, whose template `.env.dist` points `DATABASE_URL` at a local `lago_test` database. Redis must be reachable too, and ClickHouse for `clickhouse: true` specs; `.github/workflows/spec.yml` shows the other variables and the RSA keys the suite needs.

### Generated files

CI fails when these files are stale, so regenerate and commit them with the change that causes them:

- `db/structure.sql` and the schema annotations at the bottom of models, after a migration (`db:migrate` updates both in development). CI also runs every migration on an empty database.
- `schema.graphql` and `schema.json`, after any GraphQL change. This includes a new permission, enum value or webhook type.
- `config/locales/**/*.yml`, edited by hand, then normalized with `i18n-tasks normalize`.

Never edit the schema files or annotations by hand. Revert changes that do not come from your change, such as annotation churn or a `db/structure.sql` dumped from a local or test database. Running specs with pending migrations migrates the test database and rewrites both.

## Ground rules

- **Tenancy.** Load tenant data through its organization: `current_organization.customers.find_by(...)` or `Model.where(organization:)`. Every new table has a `NOT NULL` `organization_id` with a foreign key, not an organization reached `through:` another table. `spec/organization_id_column_spec.rb` fails when the column is missing (it does not check `NOT NULL` or the foreign key); never add a table to its skip list.
- **Money.** Amounts are integer `*_amount_cents` columns next to a currency. Keep unrounded values as `BigDecimal` (`precise_*_amount_cents`) and round once, at the end. Never use `Float` for money.
- **Dates.** Billing dates follow the customer timezone (`customer.applicable_timezone`, `*_in_customer_timezone` helpers), not `Time.zone`, UTC or a bare `.to_date`. Billing periods come from `Subscriptions::DatesService`.
- **Compatibility.** SDKs, lago-front and customers rely on the REST API, the webhook payloads and the GraphQL schema. Add optional fields and parameters; do not rename or remove existing ones.
- **Breaking changes.** Before rejecting input that the API accepts today (a new validation, a tighter limit, a stricter format), check how production requests and data use it, not only the code and the docs. When the input is in use, keep accepting it (for example by falling back to the previous behaviour) or put the change behind a setting, and say in the pull request what was checked.
- **Rolling deploys.** Jobs enqueued by the previous version run on the new one, so a renamed job class or a changed `perform` signature must keep accepting old jobs for one release. A new validation must accept existing rows (`validates :email, ..., if: :email_changed?`).
- **Input.** Cast and validate input before using it (`ActiveModel::Type::Boolean.new.cast`, enum values). Bad input returns a validation error, never a 500. Never interpolate input into SQL: use bind parameters or `connection.quote`.
- **Feature gating.** Premium features check `License.premium?`. Premium integrations check `organization.<integration>_enabled?` (`Organization::PREMIUM_INTEGRATIONS`), which includes the license check. A rollout flag is declared in `app/config/feature_flags.yaml`, with a description and owners, and read with `organization.feature_flag_enabled?(:name)`.
- **Scope.** Keep the diff to the task, and look for an existing helper before writing a new one. A bug fix also covers its sibling paths: REST and GraphQL, create and update services, the PostgreSQL and ClickHouse event stores.

## Services

Business logic, and every create, update or delete of a model, lives in a service in `app/services`. Model a new one on `app/services/x402/connections/create_service.rb`.

- Name it `<Namespace>::<Action>Service`, such as `Customers::CreateService`.
- It inherits `BaseService`, stores its keyword arguments in instance variables with private `attr_reader`s, then calls `super`. Its only public method is `call`, without arguments (cop `Lago/ServiceCall`), and it returns `result`.
- Declare the result: `Result = BaseResult[:customer, :subscription]`, or `Result = BaseResult` when nothing is returned.
- Callers use `Service.call(...)`, or `Service.call!(...)` to raise `BaseService::FailedResult` on failure. Never `Service.new(...).call`: it skips the middlewares (activity log, tracing).
- Fail early with `return result.not_found_failure!(resource: "customer")`. User errors use `single_validation_failure!(field:, error_code:)`, `validation_failure!(errors:)`, `record_validation_failure!(record:)`, `forbidden_failure!` (code `feature_unavailable`) or `not_allowed_failure!(code:)`. Error codes are snake_case tokens (`value_is_invalid`) that the front-end translates, not sentences.
- `service_failure!` and unknown failures become a 500 in REST and GraphQL. Keep them for real server errors.
- Never drop the failure of an inner service: check `success?` and pass it on with `result.fail_with_error!(inner_result.error)`, or use `call!`.
- Inside a transaction, enqueue jobs with `SomeJob.perform_after_commit(...)` or an `after_commit {}` block. A plain `perform_later` can run before the commit and miss the data.
- Roll back by raising. `ActiveRecord::Rollback` is ignored when an outer transaction exists.
- Serialize concurrent work on a customer with `Customers::LockService`, inside a transaction.
- `Webhooks::*` services, `CacheService` subclasses and the payment provider services built on `TypedResults` follow their own base classes. Do not use them as a model for other services.

## Jobs

- A job that runs one service has its name with `Job` (`Contracts::ActivateService` runs in `Contracts::ActivateJob`), takes positional arguments (records or ids) and calls `Service.call!`. See `app/jobs/contracts/activate_job.rb`.
- `ApplicationJob` sets Sidekiq `retry: 0`. Retries only come from `retry_on` (lock errors, `LagoHttpClient::HttpError`, `BaseService::ThrottlingError`) or an explicit `sidekiq_options retry:`; any other error sends the job to the dead set.
- Use an existing queue. Dedicated queues are enabled by a `SIDEKIQ_<NAME>` flag and fall back to a queue the default worker reads (`config/sidekiq/*.yml`). A new queue needs a Sidekiq config, a start script in `scripts/` and its own `SIDEKIQ_<NAME>` flag.
- Jobs must be idempotent. Add `unique` (usually `:until_executed, on_conflict: :log`) when the same job can be enqueued twice. Enqueue many jobs with `ApplicationJob.perform_all_later`, which raises for unique jobs.
- A new webhook `resource.action` needs a `Webhooks::<Resources>::<Action>Service` (see `app/services/webhooks/customers/created_service.rb`), an entry in `SendWebhookJob::WEBHOOK_SERVICES` and one in `config/webhook_event_types.yml`, then a GraphQL schema dump. It is sent with `SendWebhookJob.perform_after_commit("resource.action", record)`.

## REST API

- Controllers inherit `Api::BaseController`, load records through `current_organization` and call a service. See `app/controllers/api/v1/usage_attribution_types_controller.rb`.
- Every controller has a `resource_name`, an entry of `ApiKey::RESOURCES`. Without it, every API key of an organization with the `api_permissions` premium integration gets a 403, and only the `"requires API permission"` shared example catches it.
- Look records up with `find_by` and answer `not_found_error(resource: "alert")`. `find` gives a generic error code.
- Render failures with `render_error_response(result)`, records with `::V1::<Model>Serializer`, and lists with `::CollectionSerializer` and `pagination_metadata`. `create` returns 200, not 201.
- Routes go in `config/routes/shared_api.rb`, which is also served under `/api/v2` as beta. Native v2 controllers (`app/controllers/api/v2`) only cover the product catalog, taxes, contracts and what they bill (catalog invoices, product fees): cursor pagination, `app/serializers/v2`, no nested resources in lists, and a `deleted_at` on every soft-deletable record (`null` until it is deleted). Each one declares `serializable_with ::V2::<Model>Serializer` (`root:` when the JSON key is not the singular controller name, `expand_on:` for actions other than `show`) and renders with the generated `render_<root>(record)` and `render_<root plural>(relation)`, never with a serializer, a `CollectionSerializer` or a `CursorPagination::Page` built by hand. Invoices `void` is the exception: it renders a v1 invoice. A record embeds a related one only on `expands[]=<name>`, one level deep: its serializer declares `expandable :name, serializer:`, which adds `model.<name>`, or what the serializer's own private method `<name>` returns, at the end of `serialize`. See `app/controllers/api/v2/products_controller.rb`. Do not add counts of related records to v2 payloads: a client counts the related list, with `include_total_count` when it is cursor paginated. Webhooks keep the counts they already send: `plan.*` passes the internal `:counts` include of `V2::CatalogPlanSerializer`.
- Mask secret parameters in API logs with `filter_audit_log_params!`.

## GraphQL

- Mutations are `Mutations::<Resources>::<Action>`, resolvers `Resolvers::<Resource>Resolver` or `<Resources>Resolver`, types `Types::<Resources>::Object`, `CreateInput` and `UpdateInput`. Register them in `app/graphql/types/mutation_type.rb` or `query_type.rb`. See `app/graphql/mutations/usage_attribution_types/create.rb` and `app/graphql/resolvers/usage_attribution_types_resolver.rb`.
- Mutations and resolvers of the app include `AuthenticableApiUser` and `RequiredOrganization` and declare `REQUIRED_PERMISSION`, defined in `config/permissions.yml`. Some older resolvers have no permission: do not copy them. The customer portal and admin ones use their own modules.
- Return `result.success? ? result.record : result_error(result)`. Keep query logic in a query object, not in the resolver.
- Avoid N+1 queries with `dataload_association` in types. Give new enums an explicit `graphql_name`, and match field nullability to the model.

## Models and queries

- Model schema annotations are generated. Read them and `db/structure.sql` before adding an index or writing a query: avoid duplicate indexes, and remember that a composite index only serves its leftmost columns.
- Declarative class-level macros stay grouped in the declaration block at the top of the model, before any method definitions, never interleaved with instance or class methods. This covers `include`, `enum`, associations, `monetize`, `validates`, `scope`, and project macros such as `preloadable_aggregation` and `preloadable_associated_aggregation`.
- Declare enum values in a constant, then `enum :status, STATUSES, validate: true` (`validate: {allow_nil: true}` for a nullable column). New enums are PostgreSQL enums with string values: `STATUSES = {draft: "draft", active: "active"}.freeze`. Older enums use arrays on integer columns.
- Soft-deletable models use `include Discard::Model` and are never hard deleted. They set `self.discard_column = :deleted_at` and `default_scope -> { kept }`. Bulk deletion is `update_all(deleted_at: Time.current, updated_at: Time.current)` (cop `Lago/DiscardAll`). Discarding a record does not discard its children (`dependent:` does not apply), so the service discards them explicitly. Associations to a parent that can be discarded use `-> { with_discarded }`.
- `update_all` skips callbacks and `updated_at`: set `updated_at` yourself.
- Give every list query a deterministic order. `.first` and `.last` order by the UUID `id`, not by creation, and `find_by` and `take` have no order: add an explicit order whenever the record picked matters. `find_each` iterates by id, and raises in tests when the relation has an order.
- Query objects live in `app/queries` (`< BaseQuery`, `Filters = BaseFilters[...]`, `paginate` last). See `app/queries/contracts_query.rb`. Ransack attributes must be listed in `ransackable_attributes`.

## Migrations

- Create migrations with the generator. It sets the current `ActiveRecord::Migration[x.y]` version and a real timestamp. Never edit a merged migration.
- [strong_migrations](https://github.com/ankane/strong_migrations) checks every migration. Wrap an operation in `safety_assured` only when you know it is safe.
- An index on an existing table gets its own migration: `disable_ddl_transaction!`, `algorithm: :concurrently`, `if_not_exists: true`, explicit `up` and `down`, and removal of an invalid index left by a failed run. Copy `db/migrate/20261002142357_add_contracts_status_cursor_index.rb`. Columns and indexes never share a migration, except indexes declared inside `create_table`.
- `add_column`, `add_foreign_key` and `add_check_constraint` take `if_not_exists: true`, so a failed migration can be retried. Prefer `add_column` over `change_table`.
- PostgreSQL enum types are created with `create_enum`, named after the table and column (`subscription_on_termination_credit_note`).
- A constraint added with `validate: false` is validated by a second migration in the same PR. If existing rows must be fixed first, register it in `db/not_valid_constraints.yml` with a `validate_by` date, and remove the entry once the constraint is validated (`spec/db/not_valid_constraints_spec.rb` checks both). Pass `column:` to `validate_foreign_key` when a table has several foreign keys to the same table.
- Dropping a column or a table takes two releases: follow `docs/dropping_columns_and_tables.md` (cop `Lago/NoDropColumnOrTable`). Always `self.ignored_columns += [...]`, never `=`.
- Small backfills run in the migration (`Model.unscoped.in_batches.update_all`, as the default scope hides discarded rows). Large ones are a `DatabaseMigrations::*Job` started by a rake task in `lib/tasks/migrations/`, not a job enqueued by a migration. See `app/jobs/database_migrations/backfill_invoices_search_terms_job.rb`.
- SQL views use scenic: `db/views/<name>_v01.sql` with `create_view`, then a new numbered file and `update_view` for each change.

### ClickHouse

- Self-hosted migrations live in `db/clickhouse_migrate/`. ClickHouse Cloud DDL lives in `db/clickhouse_migrate/cloud/NN_*.sql`, run by hand in order when a cluster is created, so a change to an existing Cloud table is a new numbered `ALTER` script, not an edit.
- ClickHouse DDL is not transactional: one DDL change per migration, explicit `up` and `down`, `IF NOT EXISTS` and `IF EXISTS` guards.
- Kafka engine tables cannot be altered: drop and recreate the queue table and its materialized view.

## Specs

- `spec/` mirrors `app/`: a spec file is named after the class it tests, and its `RSpec.describe` names that class. Endpoint specs live in `spec/requests/api/v1` and `v2`. Billing scenarios in `spec/scenarios` go through API calls and jobs with `spec/support/scenarios_helper.rb`, rather than calling services.
- A bug fix comes with a spec that fails without the fix: run it once with the fix reverted to see it fail. Cover the negative case (a record that must not be returned) and the error paths.
- Before writing a spec, open one or two existing specs of the same kind (two `create_service_spec.rb` for a new create service) and follow their structure. Do not add top-level `describe` blocks they do not have.
- Test behaviour, not configuration: a spec for a threshold, a schedule or a webhook crosses the trigger and checks the side effect, not only the saved settings.
- A webhook or serializer spec compares the whole serialized object with `eq`, with an explicit value per field. The `creates webhook` shared example only checks the keys it is given, so a missing or renamed field still passes.
- A run counts only when its summary shows the expected number of examples and no "errors occurred outside of examples": a spec file that fails to load is left out of the count. Run new spec files on their own first.
- Helpers:
  - REST: `get_with_token(organization, path, params)` (also `post_`, `put_`, `delete_`), `json` for the parsed body, `expect(response).to be_not_found_error("alert")`, `include_examples "requires API permission", "alert", "write"`.
  - GraphQL: `execute_graphql(current_user:, current_organization:, permissions:, query:, variables:)`, `it_behaves_like "requires current user"`, `"requires current organization"` and `"requires permission", "alerts:create"`.
  - Jobs: `have_enqueued_job`, `have_been_enqueued`, `have_enqueued_job_after_commit`. Never stub or spy on job classes (cop `Lago/NoExpectReceiveOnJob`).
  - Metadata: `:premium`, `clickhouse: true`, `transaction: false`, `cache: :memory`, `:sentry`, `:bullet` (fails on N+1 queries).
- A resolver or mutation spec has one shared example per check its class makes: `"requires current user"` for `AuthenticableApiUser`, `"requires current organization"` for `RequiredOrganization`, and `"requires permission"` with the full `REQUIRED_PERMISSION` list. When a class accepts several permissions, examples pass `permissions: described_class::REQUIRED_PERMISSION.sample`, so each run uses one of them.
- `aggregate_failures` is on by default, so several expectations in one example are fine.
- Name the subject: `subject(:result) { described_class.call(...) }`. Do not test `#initialize`.
- Declare fixtures with `let`, `let_it_be` or `before`, never inside `it`, and prefer `let` with `before` over `let!`. Stub with `allow` in `before`. Vary a scenario by overriding a `let` in a nested context, not by updating records in the example, unless that update is what the spec tests.
- Prefer `build` or `build_stubbed` when the test does not need the database. Build the target factory and let its associations create the rest. Entitlement factories are `:feature`, `:privilege` and `:entitlement`.
- Freeze time with `freeze_time` or `travel_to` instead of comparing with `be_within`. Compare lists with `eq`, or `match_array` when the order does not matter, instead of several `include` checks.
- Model specs use these blocks, in this order: `describe "enums"` and `"associations"` (one `it` each, with every association option), `"Clickhouse associations"` (`clickhouse: true`), `"Scopes"` (one `describe ".scope_name"` per scope), `"validations"` (one `it`, plus a nested `describe "<attribute> validation"` for a custom validation). PostgreSQL enums use `define_enum_for(:status).backed_by_column_of_type(:enum).validating.with_values(...)`. See `spec/models/x402/settlement_spec.rb`.

### TestProf

[TestProf](https://test-prof.evilmartians.io) helpers create shared records once per example group.

- Use `let_it_be` for records that examples read and do not change (organization, customer, plan, billable metric). A `let_it_be` block cannot read a `let`.
- `let_it_be` records are frozen (`spec/spec_helper.rb`). When an example or the code under test updates one, add `refind: true` to that record only. It loads a fresh copy before each example, while `reload: true` reloads the shared instance in place.
- Use `before_all` for setup that only needs to exist, such as `before_all { create_default(:billable_metric) }`.
- `create_default(:organization)` makes factories reuse that organization. A record of another organization needs it passed explicitly (`create(:invoice, organization: create(:organization))`), and a `let_it_be` is declared after the records it depends on.
- `transaction: false` groups delete all rows after each example, which removes `let_it_be` and `before_all` records: use `let` there.

## Code Review Rules

Read the PR description first, then check the code against it and against the ground rules above.

- **Important** means it breaks behaviour, leaks data or blocks a rollback: a query not scoped to the organization, money as `Float` or rounded too early, a breaking change to the REST API, webhooks or GraphQL schema, a migration that locks a large table, a changed job signature. Naming and refactoring are nits at most.
- Do not report what CI enforces: RuboCop, `db/structure.sql`, `schema.graphql`, `schema.json`, model annotations.
- A claim about behaviour cites the `file:line` that shows it, not a guess from a method name.
- On a later review of the same PR, report only important findings on the new commits.

Also check:

- **Callers outside the diff.** Every caller of a changed method still gets what it expects: the return value, the default, the raised error.
- **Existing data.** The first run of the new code on rows written before it (defaults, `NULL`s, old enum values) works, or the PR adds a backfill or a guard.
- **Concurrency.** The same request sent twice, two writers on one record, a job running during the change. A uniqueness or ordering guarantee rests on a lock or a unique index, not on a check before the write.
- **Announced state.** For state that was sent outside (a webhook, a triggered alert, a balance shown), every event that changes its inputs has a path, both into and out of the state: configuration edits, deletion of the parent, time boundaries.
- **Errors.** A rescue catches the narrowest exception the code raises, and a spec covers it.
- **Tests.** Every new public method and branch has a spec, and the specs follow the rules above.
- **Cache keys.** When a cached value changes shape or meaning, its cache key changes in the same PR, and the PR says the cache is rebuilt once.
- **Large data.** A new or changed query on a table that grows with usage (events, fees, invoices, wallet transactions) has an index that serves it. Check the plan on a large dataset when unsure.
- **Sign-in and permissions.** A change to sign-in, tokens or permissions covers every sign-in path (password, Google, Okta, Entra ID) and both the REST and GraphQL APIs, and logs no email, token or request body.
- **Rules of this file.** A new violation of a rule here is a finding, and so is a change that makes a rule here wrong without updating it.
- **Self-contained diff.** The code does not reference a class, constant or column that neither the diff nor `main` has.

## Code style

- RuboCop (Standard, plugins and the custom cops in `dev/cops`) defines the style. Fix offenses in the files you change, and do not reformat other files.
- No `OpenStruct`: use `Struct`, `Data.define` or a hash.
- No guard clause right before the last line of a method (`return other unless condition` then `value`): write an `if`/`else` instead.
- `?` methods return booleans, and datetime columns end with `_at`.
- Comments explain why, in one or two lines. No ticket IDs, internal links or narration of the change.

## Commits and pull requests

- PRs are squash-merged, so the PR title becomes the commit on `main`. It follows Conventional Commits, `type(scope): summary`, in 72 characters or less. Types: `feat`, `fix`, `perf`, `refactor`, `chore`, `misc`, `docs`, `test`, `ci`, `build`, `revert`, `style`.
- The PR body follows `PULL_REQUEST_TEMPLATE.md` (`## Context`, `## Description`). It says why the change is needed and what it changes, without a tour of the diff, and it is updated when the approach changes.
- One concern per PR. An `AGENTS.md` rule that comes from the PR's own review is part of it.
- A change visible outside this repo also needs an update elsewhere, and the PR description says which:
  - [lago-openapi](https://github.com/getlago/lago-openapi) for a REST endpoint, parameter, field, error, limit or webhook payload.
  - [lago-doc](https://github.com/getlago/lago-doc) for a behaviour users see, a new environment variable or setting, or a step self-hosted users must take when upgrading (a page under `guide/migration`).
- When a change needs one of these updates, an agent says so and asks the user whether to prepare it. It never edits those repositories without that answer.

## Environment variables

- A new environment variable is read with a safe default, and the PR description names it with its default and purpose, so the self-hosting docs and the deployment configs can follow.
- `lago:diagnostics` prints every environment variable for support tickets and masks values by name (`Lago::Diagnostics::SECRET_PATTERN`). A variable that holds a secret has a name the pattern matches (`_KEY`, `_SECRET`, `_TOKEN`, `_PASSWORD`). If it cannot, for example a URL with a key in its path, the PR extends the masking.

## Keeping this file current

- When a review comment points out a mistake that no rule here prevents, and the lesson applies beyond this PR, the same PR adds or fixes the rule in this file. One-off choices and personal preferences stay out.
- A rule that a cop (`dev/cops`) or a spec can check goes there instead. Keep this file short: tighten or replace an existing rule rather than stacking a new one, and remove rules that no longer match the code.
- Edit `AGENTS.md`. `CLAUDE.md` only imports it.
