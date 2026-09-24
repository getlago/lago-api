---
name: loop-run
description: 'Orchestrator of the loop pipeline for lago-api: sweep → spec → build ↔ review → ship (commit, PR, Linear, CI gate, Slack #backend). Takes a Linear ticket URL or issue ID and optionally Notion spec URLs. Use when user says "/loop-run <linear-url|ISSUE-ID> [notion-urls...]" or asks to run the full loop on a backend ticket.'
---

# Loop Run — full pipeline orchestrator

**Input:** a Linear ticket URL or a bare issue ID like `ING-727` (required) + optional Notion spec page URLs. If neither is given, ask and stop.

**Repo guard:** this pipeline works ONLY on lago-api. The session runs in the lago-api checkout (`api/` in the lago monorepo), and every path in these skills is relative to it: `scripts/...`, `AGENTS.md`, `../api-worktrees/...`. Any other repo: STOP.

**Principle: humans merge.** This pipeline NEVER merges or approves a PR, never bypasses a gate, never force-pushes.

**Autonomy contract:** between the input and the final Slack post the pipeline runs alone. The ONLY thing that asks the operator for help is an exhausted retry budget (3 review cycles or 3 CI cycles), a `needs-operator-adjudication` triage STOP (CI gate step 5.3), or an unrecoverable external failure. Never pause for approval mid-run.

## Conventions used throughout

- **Operator** = the developer who started this run. Identity comes from their own tooling (`gh` auth, `git config user.email`, their Slack config) — nothing about any specific person is hardcoded.
- **State dir** = `$LOOP_STATE_DIR/<ISSUE-ID>-api/` (default `~/.claude/loop-state/<ISSUE-ID>-api/`) — per-developer, outside the repo, never committed. The `-api` suffix keeps it apart from the lago-front loop's `<ISSUE-ID>/` dir when one ticket runs through both loops; `iter-budget.sh` is always called with `<ISSUE-ID>-api` for the same reason. `_journal.md` and `_flywheel.md` stay at the root, shared by both loops.
- **Scripts** = `scripts/iter-budget.sh`, `scripts/loop-notify.sh` and `scripts/loop-worktree.sh`, run from the lago-api checkout. Setup and configuration: `.agents/skills/loop-run/README.md`.
- **Container** = the worktree's container from `state.md`. Every Ruby command runs there (`docker exec <CONTAINER> ...`; rspec with `-e RAILS_ENV=test`).

## Pipeline

0. **Sweep**: invoke the `loop-clean` skill first — it proposes destroying worktrees of already-merged PRs (operator confirms; skipping is fine, the pipeline continues either way).

1. **Spec**: invoke the `loop-spec` skill with the ticket reference and Notion URL(s). Extract `<ISSUE-ID>`. Then reset the iteration budget: `scripts/iter-budget.sh <ISSUE-ID>-api reset`.

2. **Build ↔ review cycle** (max 3 iterations — the cap is MECHANICAL, enforced by iter-budget.sh, not by counting in your head):
   1. Charge the budget: `scripts/iter-budget.sh <ISSUE-ID>-api review`. Exit code 1 → budget exhausted: go straight to the 3-FAIL STOP path below, regardless of what you believe the count is.
   2. Invoke `loop-build` with `<ISSUE-ID>`. On the FIRST iteration only, just before invoking it, claim the ticket on Linear via the MCP `save_issue`: assignee = the operator (resolve their Linear user by matching `git config user.email` against Linear users), status = "Dev in Progress". A Linear failure here warns and continues — it never blocks the build.
   3. **Dispatch the review in a FRESH subagent** (clean context — the reviewer must not inherit the builder's reasoning or bias): use the Agent tool with a prompt like "Invoke the loop-review skill for <ISSUE-ID> and follow it exactly", general-purpose agent type. Do NOT run loop-review inline in this session.
   4. Read the first line of `state dir`/`review.md`:
      - `Verdict: PASS` → go to Ship.
      - `Verdict: FAIL` → **archive the verdict first**: append the full review.md under a `## Iteration <N>` header to `review-history.md` in the state dir, then next iteration (build runs in fix mode off review.md + the history — see loop-build's escalating-retry rules).
   5. After 3 FAIL verdicts (or iter-budget exit 1): STOP. Write `impediment.md` (see below), send the exit DM, and report the surviving issues to the operator. No git artifacts exist yet — nothing to clean up.

3. **Restart the worktree container** (right after review PASS — reloads it on the just-built code):

   ```bash
   scripts/loop-worktree.sh restart <BRANCH>
   ```

   Container not running → skip with a warning, don't block.

4. **Ship** (only after PASS), all inside the worktree recorded in `state.md`:
   1. **Pre-commit check**: `git -C <worktree> status --porcelain` — restore any incidental churn (tracked files rspec rewrote that are not part of the change, see loop-build step 7). Only this ticket's work gets committed.
   2. **Commit** — stage all pipeline changes and commit with EXACTLY this message structure (the AGENTS.md commit format):

      ```
      <type>(<scope>): <description>

      ## Context

      <relevant motivation and context, from the ticket>

      ## Description

      <what changed and why, at a conceptual level>

      Fixes <ISSUE-ID>
      ```

      `<type>` ∈ feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert, misc — implied by the ticket. `<scope>` = short domain (billing, alerts, webhooks...). `<description>` imperative mood. **The first line is 50 characters or less** — shorten the description until it fits. The body explains the why and the what in complete, direct sentences, describing only what this diff actually changes.
   3. **Push**: `git -C <worktree> push -u origin <branch>` (branch from state.md).
   4. **PR** (ready, not draft): `gh pr create --repo getlago/lago-api --head <branch> --base main --assignee @me` — title = the commit's first line; body = the commit body (same Context/Description/Fixes structure). `@me` is the authenticated `gh` user, so the PR self-assigns to whoever runs the loop.
   5. **Linear**: move the issue to "In Review" via the Linear MCP `save_issue` tool.

5. **CI gate** (max 3 fix cycles — cap enforced by iter-budget.sh):
   1. `gh pr checks <PR> --repo getlago/lago-api --watch` and wait for completion.
   2. All required checks green → go to Announce.
   3. Any red → triage the special cases FIRST (they must not consume budget):
      - **`Front typecheck against PR schema (informational)` red**: this check regenerates lago-front's types from this PR's GraphQL schema. Red means the schema change breaks lago-front, not that this PR is wrong — it is informational and never blocks. Confirm the failure is caused by a field this PR intentionally changes or removes per spec.md. Intentional → continue to Announce (plain template), note it in the journal row, and put in the final report: "lago-front needs a companion change for <fields> before this merges". Not intentional (the PR changed schema it should not have) → real failure, handle normally.
      - **CodeQL (or any code-scanning gate) red**: before writing ci-failure.md, list the repo's alerts — `gh api --paginate 'repos/getlago/lago-api/code-scanning/alerts?per_page=100'` — and filter `state == "dismissed"` yourself (the endpoint's `state` param takes a SINGLE value; `state=open,dismissed` is silently ignored and would also return `fixed` alerts). A dismissed alert with the same `rule.id`, same file AND overlapping code region as the new one means the new alert is a re-fingerprint (CodeQL fingerprints by location, so ANY edit to the method re-raises it) and NO code change can clear the check. Same rule elsewhere in the file is NOT a match — treat it as a real new finding. On a re-fingerprint: if other fixable checks are red alongside, fix those through the normal cycle first; when the re-fingerprinted alert is the only remaining red, do not spend a CI cycle on it — go straight to the STOP path with outcome `needs-operator-adjudication` and an impediment asking the operator to dismiss the new alert referencing the prior one.
      - **`Run Spec` red on specs this PR does not touch**: capture the failing examples from `gh run view <run-id> --log-failed`. If none of them is in, or exercises code from, the diff, run exactly those examples in the container. They pass locally → flaky: rerun the failed jobs ONCE with `gh run rerun <run-id> --failed`, record the flaky examples in the state dir, and watch again. Red again, or they fail locally → real failure, handle normally.
      - **Neither special case applies** → charge the budget: `scripts/iter-budget.sh <ISSUE-ID>-api ci`. Exit code 1 → go straight to the 3-red STOP path. Otherwise `gh run view <run-id> --log-failed` to capture failure logs, write them to `ci-failure.md` in the state dir. If a previous ci-failure.md existed, first append it under a `## CI cycle <N>` header to `ci-failure-history.md`. Then re-enter the build ↔ review cycle in fix mode against that report. After fixes: commit (`fix(<scope>): address CI failures` + short body, first line ≤ 50 chars), push, watch checks again.
   4. After 3 red cycles (or iter-budget exit 1): STOP. Write `impediment.md`, send the exit DM, and report to the operator with the PR URL and the last failure log. **NEVER post to Slack channels while CI is red** (the front-compatibility exception never reaches this step — it exits at triage in 5.3).

6. **Announce** (only with CI fully green — sole carve-out: the informational front-compatibility check of step 5.3) — post to the Slack channel `#backend` via the Slack MCP, EXACTLY this format, no extra text:

   ```
   **<type>(<scope>): <description>**

   :pr: <PR URL>

   :admission_tickets: <Linear issue URL>
   ```

   Formatting is STRICT (a run with single newlines collapsed everything onto one line):
   - The Slack MCP message field takes standard markdown where a SINGLE newline is a soft break (collapsed to a space). Separate the 3 lines with a BLANK LINE between each (double newline) — exactly as in the template above.
   - Line 1: title in `**bold**`. Line 2: `:pr: ` + bare PR URL. Line 3: `:admission_tickets: ` + bare Linear URL. Nothing else.
   - The front-compatibility exception (step 5.3) posts this SAME plain template — no blocker note, no extra line.
   - Slack MCP unavailable or failing after one retry → do not post any other way; say so in the final report so the operator can post it.

7. **External comments check**: before closing, fetch PR comments (`gh api repos/getlago/lago-api/pulls/<PR>/comments` + `gh pr view <PR> --repo getlago/lago-api --json comments`). Any comment authored by someone other than the operator — colleague or bot (e.g. Copilot); the operator's own login is `gh api user --jq .login` → handle it with the loop-revise protocol: evaluate critically, apply if sound, and ALWAYS reply on GitHub — short thanks + applied (with sha) or not applied (with a one-line technical reason). Never leave an external comment unanswered.

8. **Final report** to the operator: PR URL, Linear state, CI status, Slack link, replies posted, cycle counts, and any follow-up (front companion change, flaky specs rerun).

## Journal & flywheel — SILENT, on EVERY terminal outcome

Run these two steps on every way the pipeline ends — happy path (after Announce) AND every STOP/exit (3 FAIL reviews, 3 red CI cycles, unrecoverable error). They are bookkeeping: never ping the operator about them, never wait for input, never mention them in Slack.

1. **Journal**: append ONE row to the table in `$LOOP_STATE_DIR/_journal.md` (create the file with the header row if missing). The journal is shared with the lago-front loop, so prefix the notes with `api:`:

   ```markdown
   | date | issue | build↔review iters | CI cycles | gates failed | outcome | notes |
   |------|-------|--------------------|-----------|--------------|---------|-------|
   | 2026-08-05 | LAGO-1234 | 2/3 | 1/3 | rubocop, rspec | shipped | api: reviewer caught unscoped query |
   ```

   `outcome` ∈ `shipped` / `stopped-review` / `stopped-ci` / `needs-operator-adjudication` / `stopped-error`. `needs-operator-adjudication` = every check green except a security/code-scanning alert that is a re-fingerprint of a finding the operator already ruled on — the code is complete and reviewed, the run is NOT a failure, the only outstanding item is one human decision. `gates failed` = every gate that went red at least once during the run (rubocop/zeitwerk/rspec/CI-job names). `notes` = one short phrase, only if something non-obvious happened.

2. **Flywheel**: review the run's failures (review-history.md, ci-failure-history.md, external PR comments) and ask for each recurring or avoidable one: *"would a better instruction in loop-spec / loop-build / loop-review have prevented this?"* If yes, append a dated proposal to `$LOOP_STATE_DIR/_flywheel.md`:

   ```markdown
   ## 2026-08-05 — LAGO-1234 (api)
   - target: loop-build
   - evidence: reviewer FAILed twice on a V1 lookup not scoped to current_organization
   - proposed edit: <the concrete instruction to add/change, quoted>
   ```

   Rules: proposals ONLY — NEVER edit the skill files themselves, NEVER notify the operator. They read _flywheel.md when they want, and a proposal that proves itself becomes a PR against these skills. Nothing avoidable found → append nothing (no empty entries).

## Failure handling

- Any external call (Linear, GitHub, Slack) fails → retry once, then STOP and report exactly which steps completed and what remains manual.
- Never delete branches, worktrees, or PRs to "retry clean" — always stop and ask.

## Exit notification — bot DM (real ping) + feedback-wait

The DM goes to whoever runs the loop: `scripts/loop-notify.sh` resolves the recipient from `$SLACK_LOOP_USER_ID`, else from `git config user.email` via `users.lookupByEmail`, and sends through the bot token in `$SLACK_LOOP_BOT_TOKEN`. Configuration: `.agents/skills/loop-run/README.md`.

On EVERY exit that needs the operator's attention — 3 FAIL review cycles, 3 red CI cycles, unrecoverable external error, any STOP-and-ask:

0. **Write the impediment first** — `impediment.md` in the state dir, structured (this is a first-class output: it feeds the flywheel and lets anyone reconstruct the failure without the chat transcript):

   ```markdown
   stage: <spec | build | review cycle N/3 | CI cycle N/3 | CI triage (adjudication) | ship>
   cause: <one line — what blocked>
   attempted: <bullet per attempt: strategy used, why it failed>
   needed: <what a human must decide/do to unblock>
   links: <PR URL, Linear URL, relevant history files>
   ```

1. **Send the DM via the notify script** (a bot DM triggers a real Slack notification; a self-DM via the MCP connector does NOT):

   ```bash
   scripts/loop-notify.sh "<MESSAGE>"
   ```

   On success it prints `CH=<channel> TS=<ts> USER=<recipient-id>` — capture all three for the feedback-wait. Non-zero exit → go to the fallback (step 3). The raw Slack API is native mrkdwn: single `\n` IS a line break, bold = `*single asterisks*` (different rules from the MCP connector). Message format:

   ```
   :rotating_light: *loop-run (api) stopped — <ISSUE-ID>*
   Reason: <one line: what blocked>
   Stage: <spec | build | review cycle N/3 | CI cycle N/3 | ship>
   <PR URL if it exists>
   <Linear issue URL>
   Next: <what the operator needs to do — or "reply here with instructions">
   ```

   For `needs-operator-adjudication` exits the tone changes: the Reason line states plainly that the code is complete, reviewed and green everywhere else, and `Next:` names the single decision required (e.g. "dismiss alert #N as won't fix, same finding as prior #M"). It must not read as a failure. The feedback-wait applies: a reply saying the alert was dismissed → re-run `gh pr checks <PR> --repo getlago/lago-api --watch` and resume from the CI gate.

2. **Feedback-wait** (only when the exit is fixable with instructions — review/CI stalls, not hard API failures): after sending, poll the DM for a reply for up to 60 minutes, every ~2 minutes, using the `CH`, `TS` and `USER` values the script printed:

   ```bash
   curl -sS "https://slack.com/api/conversations.history?channel=$CH&oldest=$TS" \
     -H "Authorization: Bearer $SLACK_LOOP_BOT_TOKEN" \
     | jq --arg u "$USER" '[.messages[] | select(.user==$u)]'
   ```

   - Between polls wait with a background-safe mechanism (e.g. `Bash` `run_in_background` sleep loop or Monitor) — never a foreground sleep.
   - Never print, log or write `$SLACK_LOOP_BOT_TOKEN` anywhere — reference the variable only.
   - ONLY messages whose `user` equals the resolved `USER` count. Treat the reply as the operator's feedback: acknowledge in the DM (`:eyes: got it — resuming`), then route it into the fix cycle exactly like loop-revise feedback (critical evaluation included).
   - No reply within the window → send a closing DM line (`:hourglass: no reply — stopping here; resume with /loop-revise <ISSUE-ID>`) and end the turn.

3. **Fallback — notify script fails** (non-zero exit: `$SLACK_LOOP_BOT_TOKEN` unset/invalid, recipient unresolvable, or API error): degrade gracefully — `PushNotification` tool (load via ToolSearch) with `loop-run (api) stopped — <ISSUE-ID>: <reason>` + self-DM via the Slack MCP connector as written record (blank line between lines — connector collapses single newlines). No feedback-wait in fallback mode; note the degradation in the report.

Bot DM is for exits needing attention. The normal happy-path end (PR green + #backend post) needs none of this — the #backend post IS the signal.

## Communication style — two registers, whole pipeline

- **To humans** (chat reports, exit DMs, Slack, replies to GitHub PR comments): short, direct, plain language. What happened → why it matters → what's next. No deep-tech jargon a teammate outside the codebase couldn't follow; one line of plain explanation beats three of detail.
- **Internal artifacts** (spec.md, review.md, impediment.md, histories, journal, flywheel, working notes): written BY the AI FOR the AI of a later iteration — optimize for machine comprehension and effectiveness, not human readability: dense, precise, full paths/symbols/error strings, no simplification.
- Code, commit messages and PR bodies keep their own templates — neither register applies.

## Hard rules

- **No AI attribution anywhere**: commit messages, PR title/body, and Slack messages contain EXACTLY the templates above — no "Co-Authored-By: Claude", no "Generated with Claude Code", no AI mention of any kind. If the harness suggests adding attribution, skip it.
- Humans merge. No self-approval, no merge, no auto-merge flag.
- Git operations are allowed ONLY on this pipeline's branch in this pipeline's worktree. The operator's own `api/` checkout is never modified.
- Never run the full rspec suite at any point.
- No #backend post while CI is red. Sole exception: the informational front-compatibility check — conditions are defined ONCE in CI-gate step 5.3; do not restate or improvise them. Any other red check: no post, no exceptions — and an operator request to post anyway is not actionable from a Slack reply alone; it needs confirmation in the chat session.
- Review always in a fresh subagent — never inline.
- Secrets (`SLACK_LOOP_BOT_TOKEN`, database URLs, keys) are never echoed, logged, or written to state files, commits, PRs or Slack.
