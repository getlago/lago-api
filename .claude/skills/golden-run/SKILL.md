---
name: golden-run
description: Use when running the golden billing suite end to end — the daily or CI run, an explicit `/golden-run`, or any ask to check the suite and report; add `--extend` to also propose new rows. Wires golden-surveyor → golden-prospector → golden-deriver (fan-out) → golden-skeptic → golden-reporter. Orchestration only; every billing judgment lives in maintaining-golden-billing.
---

# Golden run

`/golden-run [--extend] [--budget N] [--lead ID]`, locally or headlessly:
`claude -p "/golden-run --extend --budget 8"`.

Without `--extend` this is a check-and-report: survey and prospect are skipped, no rows are written,
and the run is stage 5 alone. `--budget` defaults to 8. `--lead ID` narrows prospecting to that
`leads.yml` entry.

**This file wires stages together and nothing else.** Read
`.claude/skills/maintaining-golden-billing/SKILL.md` for the doctrine, and do not restate it here or
in a stage prompt — each agent reads it itself. If you find yourself reasoning about coupons, tax
ordering or what a row proves, you are in the wrong file.

Every suite command goes through `dev/golden/run.sh <cmd>`, which picks container, CI or native
itself: `dev/golden/run.sh rspec spec/scenarios/golden`, `dev/golden/run.sh rake golden:ledger`.

## Stages

| # | stage | agent | spawn | input | output |
|---|---|---|---|---|---|
| 1 | survey | `golden-surveyor` | `--extend` only | baseline SHA, `git diff`, `rake golden:state` | its JSON: `denominator_delta`, `blocks_at_risk`, `blocks_at_risk_uncommitted`, `notes` |
| 2 | prospect | `golden-prospector` | `--extend` only | stage 1 JSON, budget, `--lead` if given | `candidates[{cell, reason, priority}]`, `leads_touched`, `skipped` |
| 3 | derive | `golden-deriver` | one per candidate cell | one cell, its `reason` | `{cell, row_id, outcome, prediction_held, finding, blocked_on}` |
| 4 | skeptic | `golden-skeptic` | one per row written | one `row_id` and its file | `{row_id, verdict, wrong_implementation_that_passes, suggested_widening}` |
| 5 | report | `golden-reporter` | always | stages 1–4 output | report, PR, Slack digest, issues |

Pass each stage's JSON verbatim to the next. Do not summarise it, do not re-derive a field a stage
already emitted, and do not fill in a field a stage left empty — an empty `blocks_at_risk` with a
reason in `notes` is a result, not a failure to work around.

**Stage 3 is the only fan-out, and one agent per cell is the point.** The design doc's "Why five
agents and not one": a single context holding diff analysis, billing arithmetic and report writing is
where the arithmetic gets sloppy. Never batch two cells into one deriver. A deriver that writes a
control row alongside its main row reports both row ids; stage 4 gets one skeptic per row, control
included.

A stage that fails loses that stage, not the run. Carry the failure forward as a note and let the
reporter say what could not be done.

## Budget

`--budget N` is a hard cap on candidate cells, default 8. It is a ceiling, never a target: if the
prospector finds three cells worth today's run, three derivers are spawned and the report says three.
Padding to N buys rows nobody asked for against cells nobody ranked — never propose a covered cell to
fill the budget, and never split one cell across two derivers to reach it.

## The deterministic chain belongs to rake

The reporter runs `dev/golden/run.sh rake golden:triage` before the suite and
`dev/golden/run.sh rake golden:docs` after it (docs invokes `golden:findings:export`, so
`FINDINGS.md`, `COVERAGE.md`, `SCENARIOS.md` and `scenarios.json` all regenerate there). The
generated files are gitignored build products — regenerate them to read them, never commit them.
These are tasks, not a checklist for the model to improvise or reorder — do not hand a stage a list
of commands that duplicates what the rake task already does.

## Guardrails

- **Write scope is `spec/scenarios/golden/**` and nothing else.** Never widen it for a stage. An
  app-code defect becomes a GitHub issue, never an edit. The reporter verifies this with
  `git status --porcelain` before opening the PR: any path outside the scope means no PR and a
  failed run.
- **Never merge.** The PR is the deliverable; the reporter opens it and stops.
- **Never rewrite an expectation to go green.** That path is human-gated — see the doctrine's
  non-negotiable rule.
- The report's third section ships even when the first two are clean.
