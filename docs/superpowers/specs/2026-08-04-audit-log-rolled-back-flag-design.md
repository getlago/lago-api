# Audit log rolled-back flag

## Context

The CS admin panel lists audit log entries and offers a rollback action on
each one. Nothing in the payload says whether an entry has already been
rolled back, so the panel shows the button on entries where it no longer
makes sense, and the API accepts the second rollback: it writes another
`rollback` entry whose `before_value` equals its `after_value`, describing a
change that did not happen.

The data needed to answer the question is already stored. A rollback entry
holds `rollback_of_id`, pointing at the entry it reverted, so an entry has
been rolled back when another entry points at it. No migration is required.

## Scope

In scope:

- Tell the panel whether an audit log entry has been rolled back.
- Refuse a second rollback of the same entry server-side.

Out of scope:

- Exposing who rolled the entry back, or when.
- Unrolling a rollback.
- Changing how entries whose action is `rollback` behave when they are
  themselves the target of a rollback: the same rule applies to them.

## Design

### The flag

`CsAdminAuditLog` gains the inverse of its existing `belongs_to :rollback_of`:

```ruby
has_one :rollback, class_name: "CsAdminAuditLog", foreign_key: :rollback_of_id, inverse_of: :rollback_of
```

`has_one` states the invariant the guard below enforces — an entry is rolled
back at most once — and a `rolled_back?` predicate returns whether that
association is present.

`Types::Admin::AuditLogType` exposes it as `rolled_back: Boolean!`, never
null: an entry either has a rollback or does not.

The audit log resolver already eager-loads the organization of each entry; it
also eager-loads the rollback, so reading the flag over a page of entries
costs one extra query rather than one per row. The `rollback_of_id` index
already exists.

### The guard

`Admin::RollbackService` refuses an entry that has already been rolled back,
returning a validation failure with the code `already_rolled_back`. The check
sits with the service's existing refusals — after the entry is found and its
feature type is confirmed rollbackable — and before anything is written, so a
refused rollback leaves no trace.

Hiding the button becomes an optimisation rather than the only defence: a
stale panel, a replayed request, or a direct API call are all refused.

### Batch consistency

`adminBatchRollback` already narrows its batch to the entries it can act on,
so unsuitable ones are skipped instead of failing the whole batch. Entries
that have already been rolled back join that filter. Without this, one
already-rolled-back entry in a batch would fail the all-or-nothing
transaction and deny every sibling its rollback.

## Testing

- Model: the association resolves both ways, and `rolled_back?` reports both
  states.
- Resolver: `rolledBack` is false for a fresh entry and true once a rollback
  points at it.
- `Admin::RollbackService`: the second rollback of an entry is refused with
  `already_rolled_back`, and no second rollback entry is written.
- `adminBatchRollback`: an already-rolled-back entry is skipped while its
  siblings in the same batch are still rolled back.
