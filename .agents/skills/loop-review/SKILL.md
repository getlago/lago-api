---
name: loop-review
description: 'Phase 3 of the loop pipeline for lago-api. Takes an ISSUE-ID, reviews the worktree diff against the ticket spec with clean context, and writes a PASS/FAIL verdict to review.md in the run state dir. Use when user says "/loop-review <ISSUE-ID>" or the loop-run orchestrator dispatches the review phase in a fresh subagent.'
---

# Loop Review — phase 3 of loop-run

**Input:** an ISSUE-ID. State dir: `$LOOP_STATE_DIR/<ISSUE-ID>-api/` (default `~/.claude/loop-state/<ISSUE-ID>-api/`). Requires `spec.md` and `state.md` (worktree path, container). If missing, stop and say which phase to run first.

**Clean context:** this skill is designed to run with NO knowledge of how the code was written (loop-run dispatches it in a fresh subagent). Judge only what spec.md, the sources it links, `AGENTS.md` and the diff say. Never assume good intent from the build phase.

## Steps

1. **Get the diff.** In the worktree from state.md:

   ```bash
   git -C <worktree> fetch origin main
   git -C <worktree> add -N . && git -C <worktree> diff origin/main --stat
   git -C <worktree> diff origin/main
   ```

   (`add -N` only marks new files so they appear in the diff — it is part of this pipeline's git exception.)

2. **Re-read the objective**: fetch the Linear ticket (and the Notion pages listed in spec.md Sources) and answer first: does this diff, as a whole, make sense for the ticket's objective? A diff can pass every mechanical check and still miss the point — that is a FAIL issue.

3. **Review the diff against spec.md, the sources and `AGENTS.md`**, checking in order:
   1. Every acceptance criterion is met by the diff (map each criterion to the code that satisfies it).
   2. No scope creep: nothing outside "Files to touch" without a justifying note in spec.md. **No incidental churn**: hunks in `db/structure.sql` or model annotation comments that do not belong to this change (rspec regenerates them from the shared test database) are a FAIL item.
   3. **No useless duplication**: no new service/query/serializer/helper that replicates an existing one; no copy-pasted logic that should be extracted or reused.
   4. **AGENTS.md compliance**: service shape (`< BaseService`, named args, private attr_readers, single `call` returning `result`, `Result` defined), job shape (same qualified name ending in `Job`, positional args, `call!`), V1 lookups scoped to `current_organization`, `create` returning 200, soft-delete via `discard`, enum constants and `validate: true`, enum values validated in the service, `organization_id` on new models, webhook services + `SendWebhookJob::WEBHOOK_SERVICES` mapping, no `OpenStruct`, no `if/unless` modifier right before the last line.
   5. **Data safety**: no N+1 on collection paths (preload/includes where records are iterated), no unscoped queries that could cross organizations, soft-deleted records not leaking through new queries, transactions around multi-record writes that must be atomic.
   6. **Migrations** (if any): strong_migrations-safe, latest migration version, real timestamp, NOT VALID constraints validated or registered in `db/not_valid_constraints.yml`, `validate_foreign_key` with `column:` when several FKs target the same table, `structure.sql` consistent with the migration. ClickHouse: explicit `up`/`down`, `IF [NOT] EXISTS` guards, one DDL concern per migration, a new numbered cloud script instead of an edited creation script.
   7. **Backward compatibility**: V1 params, serializers, GraphQL fields and webhook payloads — new optional params must not change existing behavior; removed/renamed fields are a FAIL unless the ticket requires them. GraphQL change → `schema.graphql` and `schema.json` regenerated and in the diff.
   8. **New env var** → documented in `AGENTS.md` with a masked example.
   9. **Specs**: every behavior change is covered, and specs follow the AGENTS.md Testing/Models/Factories rules (named `subject`, `let`/`before` fixtures, no `build`/`create` inside `it`, `allow` in `before` + `have_received`, `when/with/without` contexts, no new `aggregate_failures`, `build`/`build_stubbed` preferred, model spec section order). A test that would still pass if the implementation were removed is a FAIL item.
   10. **Minimal comments**: Ruby code must read by itself. A comment added or modified by the diff that narrates what code does, restates a name, or repeats AGENTS.md is a FAIL item (`redundant comment`). Only a comment explaining complex business logic the code cannot show is allowed.
   11. No dead code, no unused methods, no `pp`/`binding.pry`/`puts`/debug leftovers.
   12. Gates actually green — re-run them in the container from state.md, do not trust the build phase's claim:
       - `docker exec <CONTAINER> bundle exec rubocop <changed .rb files>`
       - `docker exec <CONTAINER> bin/rails zeitwerk:check`
       - `docker exec -e RAILS_ENV=test <CONTAINER> bundle exec rspec <spec files in the diff>` (+ `spec/graphql/lago_api_schema_spec.rb` if GraphQL changed)
       - Afterwards restore every tracked file rspec rewrote that the diff did not already contain (`git -C <worktree> checkout -- <file>`), so the review leaves the worktree exactly as it found it.

4. **Second pass with the code-review skill**: run the `/code-review` skill (working-diff reviewer) on the worktree diff and fold any confirmed findings into the issues list.

5. **Write `review.md`** in the state dir:

   PASS format:

   ```markdown
   Verdict: PASS

   ## Criteria mapping
   <one line per acceptance criterion: criterion → file/code that satisfies it>
   ```

   FAIL format:

   ```markdown
   Verdict: FAIL

   ## Issues
   1. <file:line — problem — what to change>
   2. ...
   ```

   Issues must be concrete and actionable — file, line, problem, fix direction. No style nitpicks that don't change meaning and that rubocop does not flag.

6. **Report** the verdict and (if FAIL) the issue list to the operator.

## Hard rules

- Review is read-only on the code: never fix issues yourself, only report them.
- Uncertain whether something is a real problem → it is not an issue; note it as a remark below the Issues list instead.
- Never run the full rspec suite.
- **Two communication registers**: messages to humans (chat report, notifications) = short, direct, plain language, no deep-tech jargon. Internal state files (spec.md, review.md, histories, working notes) = written for the AI of a later iteration: dense, precise, full paths/symbols/error strings — optimize for machine effectiveness, not human readability.
