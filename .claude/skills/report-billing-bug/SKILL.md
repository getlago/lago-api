---
name: report-billing-bug
description: Use when someone describes Lago billing behaving wrong in prose — a wrong total, a fee that vanished, a credit landing on the wrong invoice — and it should be recorded for the golden suite. Locates the cell, names its siblings, appends one entry to spec/scenarios/golden/leads.yml. Writes nothing else and runs nothing.
---

# Report a billing bug

`/report-billing-bug "<what Lago did wrong>"`

Steps **1. Locate** and **4. Widen** of *Investigating a reported gap* in
`.claude/skills/maintaining-golden-billing/SKILL.md`, and nothing else — read that section first.
Probing, deriving and writing the row belong to the deriver, on the next run.

## 1. Locate

Translate the prose into a block and a cell id, then grep it against the map —
`spec/scenarios/golden/SCENARIOS.md` for the tree, `scenarios.json` for the axis values. Both are
gitignored build products: run `dev/golden/run.sh rake golden:docs` first if they are absent.

- `✓` — **stop.** Report the row id from `covered_by`. A duplicate row is worse than none. If the
  reported behaviour is real, that row is wrong, which is a failure report, not a lead.
- `~` — **stop.** The cell's `external` in `scenarios.json` names the file and line guarding it. Say
  where, and that it is weaker than a golden row.
- The prose does not map cleanly onto a cell — say so and write nothing. A guessed cell wastes a
  deriver and closes a lead that is still real.
- Otherwise, continue.

## 2. Widen

Name the **siblings** — same parent, last axis varying — and the **symmetric** cell when the two axes
are of the same kind. Stop there: "similar" means adjacent in the tree, not everything that felt
related.

## 3. Write the lead

Append to `spec/scenarios/golden/leads.yml`:

```yaml
- lead: >-
    <the reporter's description: what was set up, what Lago did>
  reported: <YYYY-MM-DD>
  reported_by: <name>
  ticket: <BIL-000>
  status: open
  cells:
    - <block>/<parent>/<cell>/<surface>
    - <sibling>
  siblings_expanded: false
```

Omit `ticket` when there is none. `finding`, `siblings_note` and `siblings_done` belong to whoever
works the lead.

## Limits this skill holds itself to

It appends to `leads.yml` and touches nothing else — never a row in `matrix/`, never an `expect:`
value, never `findings.yml`, never `SCENARIOS.md`.

**A bug report is a claim, not a measurement.** The reporter read a number off a screen; nobody
derived it. The suite is worth having only because a wrong number makes it fail, so an expected value
taken from a report asserts what Lago did rather than what it owes — and when the report is slightly
off, the row bakes that mistake in and goes green forever. Deriving the number from the implementing
service is the deriver's job, on the next run, with the suite in front of them. The reporter's figure
may appear inside `lead:` as prose; never anywhere an assertion can read it.

It runs nothing: no rspec, no rake, no docker. That is what makes it usable in two minutes by someone
who is not set up.

## What happens next

The next `/golden-run` picks the lead up at prospector priority 2 and expands the siblings named here.
To work it immediately: `/golden-run --lead <ticket>`.
