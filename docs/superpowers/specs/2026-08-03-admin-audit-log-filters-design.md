# Admin audit log filters

## Context

The CS admin panel lists audit log entries through the `adminAuditLogs` GraphQL
query. That query filters by a single organization id, a single actor user id, a
feature key, a feature type and a created-at range. Two gaps make the list hard
to use once entries accumulate: an action cannot be filtered at all, and only one
organization or actor can be selected at a time.

Filtering is done by id, the way every other Lago list filter works: the panel
loads the candidate organizations and actors, then sends back the selected ids.
This spec covers the API side of those filters and the actor list the panel needs
to populate its dropdown.

The resolver was introduced on the current feature branch and is absent from
`main`, so its arguments can be renamed without breaking a released client.

## Scope

In scope:

- Filter audit log entries by action.
- Filter audit log entries by several organizations at once.
- Filter audit log entries by several actors at once.
- Expose the list of actors the panel offers in its filter dropdown.

Out of scope:

- Plural `feature_types` filter. The panel offers a single feature type today.
- Free-text search on the reason or on the organization name. Filtering is done
  by id.
- Cursor-based pagination. The list keeps the existing page/limit pagination.

## Design

### Audit log filters

`Resolvers::Admin::AuditLogsResolver` gains one argument and turns two existing
ones into lists:

| Argument | Before | After |
| --- | --- | --- |
| `organization_ids` | `organization_id: ID` | `[ID]` |
| `actor_user_ids` | `actor_user_id: ID` | `[ID]` |
| `actions` | absent | `[Types::Admin::ActionEnum]` |

`feature_key`, `feature_type`, `from_date`, `to_date`, `page` and `limit` are
unchanged.

Every filter stays optional and is applied only when provided, so an omitted or
empty filter never narrows the list. Filters combine with each other: passing
actions and organizations returns the entries matching both.

`Types::Admin::ActionEnum` already exists and is reused as the argument type, so
the accepted actions are exactly those the audit log type already returns:
`toggle_on`, `toggle_off`, `org_created` and `rollback`.

The resolver also eagerly loads the organization of each entry. The audit log
type exposes `organization_name`, which reads the association per entry and
issues one query per row today.

### Actor list

A new `Resolvers::Admin::UsersResolver`, registered as `adminCsAdmins`, returns
every user flagged as a CS admin, ordered by email. It is restricted to admin
users like the other admin queries.

The list holds every CS admin, including those who never acted, so the dropdown
stays stable and does not change as entries are created. It is small enough not
to need pagination.

Entries are returned as the existing `Types::UserType`, which already exposes the
id and email the dropdown needs.

### Organization list

The panel populates its organization dropdown with the existing
`adminOrganizations` query, which already searches by name or id and paginates.
Nothing changes there.

## Testing

Two new resolver specs, the first ones in the admin namespace:

- `spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb`: each filter in
  isolation, several values passed to the list filters, several filters combined,
  and an unfiltered query returning everything. Also asserts a non-admin user is
  rejected, like the other admin queries.
- `spec/graphql/resolvers/admin/users_resolver_spec.rb`: only CS admins are
  returned, ordering by email, and rejection of a non-admin user.
