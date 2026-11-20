# The loop pipeline (lago-api)

Takes a Linear ticket and drives it to a review-ready lago-api PR on its own: spec, build, review, ship, CI, announce in `#backend`. It runs unattended and asks for a human only when it has genuinely run out of options. It mirrors the lago-front loop (`front/.agents/skills/loop-*`), adapted to Rails.

Six skills, one per phase:

| Skill | Phase | What it does |
|---|---|---|
| `loop-run` | orchestrator | runs the whole thing; owns the retry budgets, ship, CI gate, Slack |
| `loop-clean` | sweep | destroys API worktrees whose PR is already merged (asks first) |
| `loop-spec` | 1 | reads Linear + Notion + the codebase, writes an operational spec |
| `loop-build` | 2 | implements in a dedicated worktree, writes specs, gets rubocop/zeitwerk/rspec green |
| `loop-review` | 3 | reviews the diff against the spec and AGENTS.md in a clean context, PASS/FAIL |
| `loop-revise` | post-PR | applies feedback to an open loop PR, replies to PR comments |

Usual entry point, from a Claude Code session started in `api/` (every path in the skills is relative to it):

```bash
/loop-run https://linear.app/getlago/issue/LAGO-1234/some-ticket
/loop-run LAGO-1234
```

The loop runs unattended, so start the session in a permission mode that does not prompt for each `docker exec`, `gh` and `git push`, otherwise it pauses waiting for approvals.

Optionally with Notion spec pages: `/loop-run <linear-url> <notion-url> <notion-url>`.

## Why it is built this way

The loop's quality comes from the harness, not from the prompt. Three properties are load-bearing:

- **Verification is external to the generator.** The exit condition is never "the agent thinks it is done": it is rubocop, `zeitwerk:check`, scoped rspec, a PASS verdict from a reviewer that never saw the builder's reasoning, and green CI.
- **The reviewer runs in a fresh subagent.** A builder reviewing its own work grades itself. `loop-run` dispatches `loop-review` with clean context, and the reviewer re-runs the gates instead of trusting the build phase's claim.
- **The retry budget is mechanical.** `scripts/iter-budget.sh` keeps the counters on disk and refuses the fourth attempt. The cap does not depend on the agent remembering how many times it has tried.

## Setup, per developer

Nothing about any specific person is in these files. Each developer configures their own identity and the loop follows it.

**1. Required tooling**

- `gh` authenticated (`gh auth status`) — the PR self-assigns to whoever runs the loop.
- Docker dev stack up (`lago_api_dev`, `lago_db_dev`, `lago_redis_dev`, `lago_clickhouse_dev` running).
- MCP connectors: Linear (read ticket, assign, move to In Review), Notion (specs), Slack (the `#backend` announcement).
- `jq` and `curl` for the notification script (`brew install jq`).

**2. Slack bot, for the "I'm stuck" DM**

The loop DMs you when it gives up. It needs a bot token because a self-DM through the MCP connector does not raise a real notification. The lago-front loop uses the same bot and the same variables — if you already set it up there, skip to step 4.

Create a small Slack app (or reuse a shared one), install it in the workspace, and give it these bot scopes:

- `chat:write` — send the DM
- `im:write` — open the DM channel
- `im:history` — read your reply, so the loop can resume from your instructions
- `users:read.email` — optional, only if you want the recipient resolved from your git email

**3. Environment**

Put these in your shell profile (e.g. `~/.zshrc`) or in your own untracked `.claude/settings.local.json` under `"env"` — never in a tracked file:

| Variable | Required | Meaning |
|---|---|---|
| `SLACK_LOOP_BOT_TOKEN` | for the DM | bot token of the app above (`xoxb-***`). Secret. Without it the loop still runs, but a stuck run falls back to a desktop notification and cannot read your reply |
| `SLACK_LOOP_USER_ID` | recommended | your Slack member ID (profile → ⋮ → Copy member ID). Not a secret. Unset → the script looks you up by `git config user.email`, which only works if that is your work email and the app has `users:read.email` |
| `LOOP_STATE_DIR` | no | where run state lives. Default `~/.claude/loop-state` |
| `ITER_MAX` | no | attempts allowed per retry budget. Default `3` |
| `ITER_STATE_DIR` | no | where `iter-budget.sh` keeps its counters. Falls back to `LOOP_STATE_DIR`. Only set it to the **same** root as `LOOP_STATE_DIR` |

None of these are read by the Rails app; they only drive the scripts in `scripts/`.

**4. Verify**, from `api/`:

```bash
scripts/loop-notify.sh --check
```

Prints the resolved recipient and DM channel without sending anything.

## Worktrees

Each run builds in `lago/api-worktrees/<ISSUE-ID>-<slug>`, created by `scripts/loop-worktree.sh` from `origin/main`. Your own `api/` checkout and its current branch are never touched. The worktree gets its own container, `lago_api_wt_<slug>`, on the dev stack network: it shares Postgres, Redis and ClickHouse with `lago_api_dev`, runs no server, and only hosts `docker exec` commands (rubocop, zeitwerk, rspec).

```bash
scripts/loop-worktree.sh ps                 # list loop containers
scripts/loop-worktree.sh restart <branch>   # restart one
scripts/loop-worktree.sh destroy <branch>   # remove container, worktree and local branch (asks)
```

The test database is shared with your other checkouts. rspec regenerates `db/structure.sql` and model annotation comments from whatever state that database is in, so the loop restores every file it did not mean to change after each test run.

## Team policies this pipeline assumes

Adopting the loop means accepting these. They are enforced in the skills as hard rules.

- **The pipeline commits, pushes and opens the PR.** It is the one place where an agent performs git write operations, and only ever on its own branch in its own worktree. It never force-pushes and never touches the main checkout.
- **Humans merge.** No self-approval, no merge, no auto-merge flag — ever.
- **No AI attribution** in commits, PR bodies or Slack messages.
- **Commits follow AGENTS.md**: conventional type, first line of 50 characters or less, `## Context` / `## Description` body.
- **`#backend` is posted only when CI is green** — sole exception: the informational front-compatibility check, red because the PR intentionally changes GraphQL schema lago-front uses. The final report then names the lago-front companion change needed.
- **The full rspec suite is never run.** Only the spec files of the touched domain.
- **Minimal comments.** Ruby code is descriptive by itself; a comment is only for complex business logic.
- **Every external PR comment gets a reply** — applied with the sha, or not applied with a one-line technical reason.
- **Destructive cleanup always asks.** `loop-clean` never destroys a dirty worktree or one with unpushed commits.

## Run state

Per-developer, outside the repo, in `$LOOP_STATE_DIR/<ISSUE-ID>-api/` (the `-api` suffix keeps it apart from the lago-front loop's dir for the same ticket):

| File | Written by | Purpose |
|---|---|---|
| `spec.md` | loop-spec | the operational spec the whole run is judged against |
| `state.md` | loop-build | worktree path, branch, container |
| `review.md` | loop-review | current PASS/FAIL verdict |
| `review-history.md` | loop-run | every previous FAIL verdict — fuel for the escalating retry |
| `ci-failure.md` / `ci-failure-history.md` | loop-run | current and past CI failure logs |
| `feedback.md` | loop-revise | every round of human feedback |
| `impediment.md` | loop-run / loop-revise | why the loop gave up: stage, cause, what it tried, what it needs |
| `counters/` | iter-budget.sh | the retry budgets |

Plus two files shared across runs and with the lago-front loop: `_journal.md` (one row per run — iterations spent, gates that failed, outcome; API rows noted `api:`) and `_flywheel.md` (proposals to improve these skills).

## Improving the loop

Every run that struggles writes down why. `_flywheel.md` collects proposed edits to the skills, evidence attached; the loop never edits its own instructions. Read it when you have a moment, and turn a proposal that keeps recurring into a PR against `.agents/skills/loop-*`. `_journal.md` is how you tell whether such a change actually helped — average iterations per run should fall.

Scripts live in `api/scripts/`: `iter-budget.sh` (retry budget), `loop-notify.sh` (exit DM) and `loop-worktree.sh` (worktree + container). All are standalone and documented in their headers.
