---
name: loop-spec
description: 'Phase 1 of the loop pipeline for lago-api. Takes a Linear ticket URL or issue ID (required) and optionally Notion spec page URLs, reads all sources, explores the lago-api codebase, and writes an operational spec to the run state dir. Use when user says "/loop-spec <linear-url|ISSUE-ID> [notion-urls...]" or asks to spec a ticket for the loop pipeline.'
---

# Loop Spec — phase 1 of loop-run

**Input:** a Linear ticket URL or a bare issue ID like `ING-727` (REQUIRED — it provides the ISSUE-ID that keys the whole pipeline), plus optionally one or more Notion page URLs with product/technical specs. Both can be given together.
If no Linear ticket was provided, ask for it with AskUserQuestion and stop until given.

**Repo:** the lago-api checkout, `api/` inside the lago monorepo — the session's working directory. If the current session is not in the lago-api checkout, STOP — this pipeline is lago-api only.

**State dir:** `$LOOP_STATE_DIR/<ISSUE-ID>-api/` (default `~/.claude/loop-state/<ISSUE-ID>-api/`) — per-developer, outside the repo, never committed.

## Steps

1. **Extract the issue ID** from the URL or the bare ID (pattern `[A-Z]+-\d+`, uppercase — any Linear team prefix: LAGO, ING, ...). All state for this run lives in the state dir — create the directory.

2. **Fetch all sources**:
   - Linear ticket via the Linear MCP `get_issue` tool — the WHOLE ticket, not just the description: title, description, acceptance criteria, current state, labels, relations (blocked-by/related/duplicates), attachments. Then fetch the full comment thread via `list_comments`: comments often carry decisions, scope changes and repro details that never made it back into the description — on conflict, a later comment overrides the description; note it in spec.md.
   - Every Notion URL given, via the Notion MCP `notion-fetch` tool: product requirements, technical constraints, edge cases.
   - If a Notion page linked INSIDE the Linear ticket clearly holds the product/tech spec, fetch that too.
   - Conflict between sources → the Linear ticket wins for scope, Notion wins for product detail; note the conflict in spec.md.

3. **Explore the codebase.** Locate every file the ticket touches: models, services (`app/services/**`), jobs, V1 controllers and serializers, GraphQL types/mutations/resolvers, webhooks (`app/services/webhooks/`, `SendWebhookJob::WEBHOOK_SERVICES`), queries, migrations, ClickHouse migrations, and the matching specs. Follow existing patterns — read neighboring code, don't invent structure. Note in spec.md which of these apply:
   - GraphQL schema changes → `schema.graphql` and `schema.json` must be regenerated (`spec/graphql/lago_api_schema_spec.rb` enforces it), and the front-compatibility check may flag a needed lago-front companion change.
   - Postgres migration → `db/structure.sql` changes, model annotations change, strong_migrations applies, NOT VALID constraints follow the AGENTS.md rule.
   - ClickHouse schema change → the AGENTS.md ClickHouse migration rules (self-hosted migration + a new numbered `db/clickhouse_migrate/cloud/*.sql` script).
   - Public API change (V1 params, serializers, webhooks payloads) → backward compatibility; new optional params must not break existing behavior.
   - New environment variable → it must be documented in `AGENTS.md`.

4. **Write `spec.md`** in the state dir, with exactly these sections:

   ```markdown
   # <ISSUE-ID>: <ticket title>

   ## Sources
   - Linear: <linear URL — from `get_issue` when only the ID was given>
   - Notion: <each notion URL, or "none">

   ## Summary
   <2-4 sentences: what changes and why>

   ## Acceptance criteria
   <numbered list, testable statements, taken/derived from the ticket>

   ## Files to touch
   <bullet list of exact paths relative to api/, one line each with what changes there, specs included>

   ## Impact flags
   <each that applies: graphql-schema | postgres-migration | clickhouse-migration | public-api | new-env-var | webhook — or "none">

   ## Non-goals
   <what is explicitly out of scope>

   ## Verification
   - `bundle exec rubocop <changed files>`
   - `bin/rails zeitwerk:check`
   - `bundle exec rspec <exact spec files for the touched domain>`
   <optional: `bin/rails graphql:schema:dump` + clean-diff check if graphql-schema>
   <optional: `bin/rails db:migrate` + structure.sql check if postgres-migration>
   ```

5. **Report** the spec path and a 3-line summary to the operator.

## Hard rules

- Read-only on Linear: no comments, no state changes in this phase.
- No code edits in this phase. No files written inside the repo.
- If the ticket lacks enough detail to write testable acceptance criteria, STOP and ask the operator — never guess.
- **Two communication registers**: messages to humans (chat report, notifications) = short, direct, plain language, no deep-tech jargon. Internal state files (spec.md, review.md, histories, working notes) = written for the AI of a later iteration: dense, precise, full paths/symbols/error strings — optimize for machine effectiveness, not human readability.
