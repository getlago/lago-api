---
name: loop-build
description: 'Phase 2 of the loop pipeline for lago-api. Takes an ISSUE-ID, reads spec.md from the run state dir, implements the change in a dedicated worktree, writes the specs, and gets rubocop + zeitwerk + scoped rspec green. Use when user says "/loop-build <ISSUE-ID>" or the loop-run orchestrator invokes the build phase.'
---

# Loop Build — phase 2 of loop-run

**Input:** an ISSUE-ID (e.g. `LAGO-1745`). State dir: `$LOOP_STATE_DIR/<ISSUE-ID>-api/` (default `~/.claude/loop-state/<ISSUE-ID>-api/`). Requires `spec.md` there — if missing, stop and tell the operator to run loop-spec first.

**Repo:** the lago-api checkout (the session's working directory, `api/` in the lago monorepo); worktrees in `../api-worktrees/` beside it, managed by `scripts/loop-worktree.sh`. Every path below is relative to the checkout.

**Running commands:** every Ruby command runs inside the worktree's container (the worktree is mounted at `/app`), never on the host and never in `lago_api_dev`:

```bash
docker exec <CONTAINER> bundle exec rubocop <files>
docker exec -e RAILS_ENV=test <CONTAINER> bundle exec rspec <spec files>
```

`<CONTAINER>` comes from state.md. rspec always needs `-e RAILS_ENV=test`.

## Modes

- **Fresh build**: no `review.md` in the state dir, or it says PASS.
- **Fix mode**: `review.md` has verdict FAIL, or `ci-failure.md` was just written by loop-run — fix ONLY the numbered issues / CI failures listed there, nothing else. Reuse the existing worktree from `state.md`.

## Steps (fresh build)

1. **Preflight** (all must hold, else STOP and ask the operator):
   - Main docker stack running: `docker ps --format '{{.Names}}' | grep -x lago_api_dev`.
   - Latest `main` fetched: `git fetch origin main`. The worktree branches from `origin/main`, so the operator's own checkout and its current branch are never touched. If the fetch fails, STOP.
   - If an `../api-worktrees/<ISSUE-ID>-*` dir already exists from an aborted run, STOP and ask — never delete or force.

2. **Create the worktree**:

   ```bash
   scripts/loop-worktree.sh create <BRANCH> --from=origin/main
   ```

   It creates the git worktree, copies `config/keys`, starts the container and waits until `bundle install` finished. It prints `worktree:`, `branch:` and `container:`.

   **Branch naming** — `<BRANCH>` = `<ISSUE-ID>-<topic-slug>`: the Linear issue ID first, UPPERCASE, then a short kebab-case slug of the ticket's main topic (3-6 words). Examples: `ING-517-lock-alert-on-evaluation`, `LAGO-5739-add-customer-billing-entity-filter`. Worktree dir name = branch name. The session stays in the `api/` checkout — operate on the worktree via `git -C` and `docker exec`.

3. **Record state**: write `state.md` in the state dir (the state dir stays keyed on the bare ISSUE-ID):

   ```markdown
   worktree: <absolute path to ../api-worktrees/<BRANCH>>
   branch: <BRANCH>
   container: <container printed by loop-worktree.sh>
   ```

4. **Load the coding rules**: read `AGENTS.md` in full. It is the styleguide for this pipeline — every rule in it is binding (services, jobs, controllers, models, enums, webhooks, migrations, ClickHouse migrations, backward compatibility, environment variables, testing, factories).

5. **Implement** per spec.md, inside the worktree only:
   - Follow "Files to touch" — if reality diverges from the spec, update spec.md with a note and continue only if the divergence is minor; otherwise stop and report.
   - **Reuse first**: before writing a new service, query, serializer, concern or helper, search for one that already does the job — reuse or extend, never duplicate.
   - **AGENTS.md shapes, not improvisation**: a service extends `BaseService`, takes named args, has private attr_readers, a single `call` returning `result`, and a `Result`; a job mirrors the service's fully qualified name, takes positional args and calls `call!`; V1 lookups are scoped to `current_organization`; soft-deletable models use `discard`/`discard_all!`; enum values are validated in the service; new models store `organization_id`.
   - **Code reads by itself — minimal comments.** Ruby code must be descriptive through naming and structure. Add a comment ONLY to explain complex business logic whose why the code cannot show (a billing rule, a non-obvious ordering constraint, a cross-file invariant). Never narrate what a method, variable or line does. When a change removes the logic a comment explained, delete the comment.
   - No dead code, no unused methods, no code built for a future consumer that does not exist yet. No `pp`, `binding.pry`, `puts`, or `OpenStruct`.
   - Match the AGENTS.md style rule on conditionals: no `if`/`unless` modifier right before the last line — use an explicit `if/else/end`.
   - **Migrations** (postgres-migration flag): real timestamp from `date +"%Y%m%d%H%M%S"`, latest `ActiveRecord::Migration[x.y]`, strong_migrations-safe (`safety_assured` only when justified), NOT VALID constraints validated in a follow-up migration or registered in `db/not_valid_constraints.yml`. Run `docker exec -e RAILS_ENV=test <CONTAINER> bin/rails db:migrate` and keep in `db/structure.sql` and in the model annotations ONLY the hunks this migration produces.
   - **GraphQL** (graphql-schema flag): regenerate with `docker exec <CONTAINER> bin/rails graphql:schema:dump` and include `schema.graphql` + `schema.json`.
   - **New env var** (new-env-var flag): document it in `AGENTS.md` (name, purpose, masked example).

6. **Specs — ALWAYS**: write or update specs for every behavior change, following the AGENTS.md "Testing", "Models" and "Factories" sections to the letter (named `subject`, `let`/`before` for fixtures, `allow` in `before` + `have_received`, context wording `when/with/without`, no `aggregate_failures`, `build`/`build_stubbed` over `create` when persistence is not needed, grouped enums/associations/validations blocks for models). Every new service, job, controller action, GraphQL mutation/resolver and webhook gets a spec.

7. **Gates** (run in the container, all must pass):
   - `bundle exec rubocop <every changed or added .rb file>` (use `-a` first if there are autocorrectable offenses, then re-run without it)
   - `bin/rails zeitwerk:check`
   - `bundle exec rspec <the spec files for the touched domain>` with `-e RAILS_ENV=test`. NEVER run the full suite (`rspec` with no path, or a whole top-level dir like `spec/services`, is FORBIDDEN).
   - graphql-schema flag → `bundle exec rspec spec/graphql/lago_api_schema_spec.rb` too.
   - **Restore incidental churn after every rspec run**: the test database is shared with the operator's other checkouts, so rspec rewrites `db/structure.sql` and the schema annotation comments of unrelated models from whatever state that database is in. Run `git -C <worktree> status --porcelain`, and `git -C <worktree> checkout -- <file>` every tracked file this change did not intend to modify. For a file the change did modify (e.g. `structure.sql` with a migration), drop the unrelated hunks. The diff must contain only this ticket's work.

8. **Report**: diff stat + gates output summary. Do NOT commit — shipping happens in loop-run after review PASS.

## Steps (fix mode)

1. Read the numbered issues from `review.md` (or the failure report in `ci-failure.md`).
2. **Escalating retry — attempt N>1 must not be a blind rerun of attempt N-1:**
   - Read the full history too: `review-history.md` / `ci-failure-history.md` in the state dir (written by loop-run before each re-entry).
   - Before coding, state explicitly (in your working notes for the report): for each issue, what the previous attempt did and what THIS attempt does differently.
   - **Same issue failed twice** → the previous strategy is wrong, don't refine it a third time in the same direction: change strategy — re-read spec.md acceptance criteria from scratch, broaden the investigation (callers, related services, existing specs), question the diagnosis itself. Consume the retry, but on a different path.
   - **Oscillation check**: before applying a fix, verify against the history that it does not revert (fully or partially) a change made by a PREVIOUS iteration. Fix A breaks B, fix B re-breaks A is a loop-killer the gates won't surface. Detected → declare it in the report, do NOT apply either of the two oscillating fixes again: find the third option that satisfies both constraints (usually one level up from where both fixes were applied). Note the oscillation in the working notes so loop-run's flywheel picks it up.
   - Never STOP early for a repeated failure — the 3-attempt budget belongs to loop-run and is enforced by `scripts/iter-budget.sh`; exhausting it is the ONLY human touchpoint.
3. Fix only those issues in the existing worktree.
4. Re-run the gates (step 7 above), including the churn restore. If the fix changed behavior, update the specs for it.
5. Report what changed per issue number, including the "what's different from the previous attempt" line for each.

## Hard rules

- All edits in the worktree, never in the main checkout.
- No commit, no push, no PR in this phase.
- Never run the full rspec suite.
- Ruby commands only inside the worktree container.
- Minimal comments: only for complex business logic.
- **Two communication registers**: messages to humans (chat report, notifications) = short, direct, plain language, no deep-tech jargon. Internal state files (spec.md, review.md, histories, working notes) = written for the AI of a later iteration: dense, precise, full paths/symbols/error strings — optimize for machine effectiveness, not human readability.
