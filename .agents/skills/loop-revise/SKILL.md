---
name: loop-revise
description: 'Post-PR revision phase of the loop pipeline for lago-api. Takes an ISSUE-ID and feedback on the open PR, applies ONLY the requested changes in the existing worktree, re-runs gates, commits, pushes, and watches CI. Use when user says "/loop-revise <ISSUE-ID> <feedback>", or asks to change something in an API PR the loop opened.'
---

# Loop Revise — apply feedback to an open loop PR

**Input:** a task reference + feedback. The reference can be ANY of:
- an ISSUE-ID (`ING-538`) — direct key of the state dir;
- a PR number (`6476` / `#6476`) or PR URL — resolve it: `gh pr view <n> --repo getlago/lago-api --json headRefName` → branch → the `$LOOP_STATE_DIR/*-api/state.md` whose `branch:` matches → that dir's ISSUE-ID.

**State dir:** `$LOOP_STATE_DIR/<ISSUE-ID>-api/` (default `~/.claude/loop-state/<ISSUE-ID>-api/`).

Resolution fails (no matching `*-api` state dir) → STOP: this PR was not produced by the API loop; say so. Feedback comes in two forms, both handled:
- **The operator's free text** (chat, Slack reply) — the operator is the developer running the loop, i.e. the PR author.
- **GitHub PR comments from others** — colleagues or bots (e.g. Copilot). Fetch them:
  ```bash
  gh api repos/getlago/lago-api/pulls/<PR>/comments               # review comments (inline)
  gh pr view <PR> --repo getlago/lago-api --json comments         # issue-level comments
  ```
  Skip comments authored by the operator themselves (`gh api user --jq .login` — those are their own notes) and already-replied ones.

No free-text feedback given → default to the unanswered external PR comments as the feedback set. No unanswered comments either → report "nothing to revise" and stop.

**Preconditions:** `state.md` exists in the state dir (worktree, branch, container) and the PR for `<ISSUE-ID>` is OPEN (`gh pr view <branch> --repo getlago/lago-api --json state`). PR MERGED or CLOSED → STOP: nothing to revise, suggest a new ticket instead. Container not running → `scripts/loop-worktree.sh restart <branch>`.

## Steps

1. **Record the feedback**: append it to `feedback.md` in the state dir with a timestamp header (keep prior rounds — history matters).

2. **Evaluate the feedback CRITICALLY — before touching any code.** You are a senior peer, not an executor. Check each feedback point against: the spec's acceptance criteria, the ticket objective (Linear/Notion), `AGENTS.md`, and the actual code. Then classify it:
   - **Sound** → say why in one line, proceed.
   - **Sound but better done differently** → propose the alternative with reasoning (e.g. "renaming works, but that service is called from 7 places — extracting X instead touches 1"); let the operator pick.
   - **Breaks an acceptance criterion, duplicates existing code, contradicts AGENTS.md, breaks backward compatibility, or degrades the code** → PUSH BACK: explain concretely what it breaks and what you'd do instead. Do NOT apply it. Apply only if the operator confirms after hearing the objection — then note the override in feedback.md.
   - Verify claims before agreeing: if the feedback asserts something about the code ("this triggers an N+1"), check it in the code first. Never implement performatively to please.
   - This evaluation applies IDENTICALLY to external comments (colleagues/bots): a Copilot suggestion gets the same scrutiny as anyone else's. For external feedback, "push back" means the polite not-applied reply of step 8 — only escalate to the operator when the comment is sound but conflicts with the spec.

3. **Apply — ONLY the agreed points.** In the worktree from state.md:
   - No opportunistic refactors, no scope creep beyond the agreed feedback.
   - Same build rules as loop-build: AGENTS.md shapes, reuse first, minimal comments (only for complex business logic), no dead code, specs for every behavior change.
   - Feedback ambiguous → STOP and ask before coding.

4. **Gates** (in the container, all must pass):
   - `docker exec <CONTAINER> bundle exec rubocop <changed .rb files>`, `docker exec <CONTAINER> bin/rails zeitwerk:check`.
   - `docker exec -e RAILS_ENV=test <CONTAINER> bundle exec rspec <affected spec files>` — scoped only, NEVER the full suite. GraphQL changed → regenerate the schema dump and run `spec/graphql/lago_api_schema_spec.rb`.
   - Restore incidental churn rspec leaves behind (loop-build step 7).

5. **Restart the worktree container**: `scripts/loop-worktree.sh restart <BRANCH>`. Container not running → skip with a warning, don't block.

6. **Commit and push** on the existing branch:

   ```
   fix(<scope>): address review feedback

   ## Description

   <bullet list: each feedback point → what changed>

   Refs <ISSUE-ID>
   ```

   First line 50 characters or less. Then `git -C <worktree> push` — the open PR updates itself.

7. **CI gate**: `gh pr checks <PR> --repo getlago/lago-api --watch`. Red → same recovery as loop-run, INCLUDING its pre-budget triage of special cases (front-compatibility check, code-scanning re-fingerprint, flaky unrelated specs — loop-run CI-gate step 5.3); none applies → charge the budget first with `scripts/iter-budget.sh <ISSUE-ID>-api ci-revise` (exit 1 = exhausted → STOP path), capture failed logs to `ci-failure.md` (previous one appended to `ci-failure-history.md`), fix, recommit. On STOP: write `impediment.md` and notify exactly like loop-run's "Exit notification" section — send via `scripts/loop-notify.sh "<MESSAGE>"` (prints `CH`/`TS`/`USER` for the feedback-wait polling); fallback to PushNotification + MCP self-DM if the script fails.

8. **Reply to every external comment on GitHub — ALWAYS** (colleagues and bots alike, whether the suggestion was applied or not). Short, friendly, in English, no AI attribution:
   - Applied → thank + confirm: `Good catch, thanks! Applied in <short-sha>.`
   - Not applied → thank + brief concrete reason: `Thanks for the suggestion! Leaving as is: <one-line reason — e.g. this matches the pattern used in X / the spec requires Y>.`
   - Inline review comments: reply in-thread via `gh api repos/getlago/lago-api/pulls/<PR>/comments/<comment-id>/replies -f body='...'`. Issue-level comments: `gh pr comment <PR> --repo getlago/lago-api --body '...'`.
   - Never leave an external comment unanswered; never be dismissive — the reason must be technical, one or two lines max.

9. **Journal & flywheel — SILENT bookkeeping, before the report:**
   - Append a row to `$LOOP_STATE_DIR/_journal.md`. It shares loop-run's table, so it must have EXACTLY 7 cells in this order — a misaligned row makes the whole table unreadable:

     ```markdown
     | <date> | <ISSUE-ID> | <N> points | <charged>/<max> | <gates that went red, or none> | revised | api: <one short phrase> |
     ```

     Column 3 is how many feedback points were applied (not build↔review iterations, which this phase does not run). Column 4 is the `ci-revise` budget as `N/3`, or `0/3` if CI never went red. Column 6 is `revised`, `stopped-ci`, or `needs-operator-adjudication` (loop-run's definition). Everything narrative belongs in column 7 and nowhere else.
   - **Flywheel**: the operator's feedback is the highest-value signal — for each point raised, ask *"would a better instruction in loop-spec / loop-build / loop-review have prevented the loop from producing this in the first place?"* If yes, append a dated proposal to `$LOOP_STATE_DIR/_flywheel.md` (target skill, evidence, proposed edit — quoted). Proposals ONLY: never edit skill files, never ping the operator about it. Nothing avoidable → append nothing.

10. **Report**: what changed per feedback point, replies posted, commit SHA, CI status. **NO new #backend post** — the PR was already announced; colleagues see the update on GitHub.

## Hard rules

- **No AI attribution**: commit message contains exactly the template above — no Co-Authored-By: Claude, no "Generated with" lines.
- Only the existing worktree and branch from state.md — never a new branch, never the main checkout.
- Only the changes the feedback asks for.
- Humans merge. Never merge, never approve.
- Never run the full rspec suite.
- No #backend repost.
- **Two communication registers**: messages to humans (chat report, notifications, GitHub PR comment replies) = short, direct, plain language, no deep-tech jargon. Internal state files (spec.md, review.md, histories, working notes) = written for the AI of a later iteration: dense, precise, full paths/symbols/error strings — optimize for machine effectiveness, not human readability.
