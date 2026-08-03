# Admin Audit Log Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the CS admin panel filter audit log entries by action and by several organizations or actors at once, and expose the CS admin list its actor dropdown needs.

**Architecture:** Two GraphQL changes in the admin namespace. `Resolvers::Admin::AuditLogsResolver` turns its two single-id arguments into id lists and gains an `actions` list argument, keeping the inline `where` chaining already used there. A new `Resolvers::Admin::UsersResolver`, registered as `adminCsAdmins`, returns CS admin users for the dropdown. No query object, no new GraphQL type: `Types::Admin::ActionEnum` and `Types::UserType` already exist.

**Tech Stack:** Ruby on Rails, graphql-ruby, Kaminari pagination, RSpec, FactoryBot.

## Global Constraints

- Specs run in the API container: `lago exec api bundle exec rspec <args>`.
- The GraphQL schema dump is checked in. After any change to arguments, types or fields, regenerate it with `lago exec api bundle exec rake graphql:schema:dump` and commit `schema.graphql` and `schema.json`.
- Running specs makes the `annotate` gem rewrite model annotations. Before committing, check `git status` and `git checkout --` any file you did not intend to change (`app/models/metadata/item_metadata.rb` is a known offender).
- GraphQL arguments and fields are declared in alphabetical order in this codebase. Keep them sorted.
- Admin GraphQL resolvers authenticate through `AuthenticableAdminUser`, which requires `context[:current_user]` to be a `cs_admin?` user whose email ends with `@getlago.com`. Spec actors must satisfy all three, e.g. `create(:user, email: "cs@getlago.com", cs_admin: true)`.
- A `[ID]` argument renders as `[ID!]` in the schema, so spec query variables are declared `[ID!]`.
- Never use `aggregate_failures` in new tests. Use `let!` only for records that must exist before the example runs.
- Commit messages follow Conventional Commits with the `## Context` / `## Description` body, and end with the line `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

## File Structure

- `app/graphql/resolvers/admin/audit_logs_resolver.rb` — modified. Arguments and filter chain of the audit log list.
- `app/graphql/resolvers/admin/users_resolver.rb` — created. Lists CS admin users for the actor dropdown.
- `app/graphql/types/query_type.rb` — modified. Registers the new `adminCsAdmins` field.
- `spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb` — created. Covers each filter, list filters with several values, combined filters, and authorization.
- `spec/graphql/resolvers/admin/users_resolver_spec.rb` — created. Covers the returned set, its ordering, and authorization.
- `schema.graphql`, `schema.json` — regenerated in both tasks.

---

### Task 1: Audit log list filters

**Files:**
- Modify: `app/graphql/resolvers/admin/audit_logs_resolver.rb`
- Test: `spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb` (create)
- Modify: `schema.graphql`, `schema.json` (regenerated)

**Interfaces:**
- Consumes: `CsAdminAuditLog` (scope `newest_first`, enum `action` with values `toggle_on`, `toggle_off`, `org_created`, `rollback`), `Types::Admin::ActionEnum`, `Types::Admin::FeatureTypeEnum`, `Types::Admin::AuditLogType`.
- Produces: the `adminAuditLogs` query accepting `actions: [AdminActionEnum!]`, `actorUserIds: [ID!]`, `organizationIds: [ID!]`, `featureKey: String`, `featureType: AdminFeatureTypeEnum`, `fromDate: ISO8601Date`, `toDate: ISO8601Date`, `page: Int`, `limit: Int`. The arguments `actorUserId` and `organizationId` no longer exist.

- [ ] **Step 1: Write the failing spec**

Create `spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Admin::AuditLogsResolver do
  let(:query) do
    <<~GQL
      query($actions: [AdminActionEnum!], $actorUserIds: [ID!], $organizationIds: [ID!]) {
        adminAuditLogs(actions: $actions, actorUserIds: $actorUserIds, organizationIds: $organizationIds) {
          collection { id action actorEmail organizationId organizationName }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:other_admin) { create(:user, email: "support@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, name: "ACME Corp") }
  let(:other_organization) { create(:organization, name: "Hooli") }

  let!(:toggle_on_log) do
    create(:cs_admin_audit_log, organization:, actor_user: admin_user, action: :toggle_on)
  end

  let!(:org_created_log) do
    create(:cs_admin_audit_log, organization:, actor_user: other_admin, action: :org_created)
  end

  let!(:other_org_log) do
    create(:cs_admin_audit_log,
      organization: other_organization,
      actor_user: other_admin,
      action: :toggle_off,
      after_value: false)
  end

  def fetch(variables = {})
    result = execute_graphql(current_user: admin_user, query:, variables:)
    result["data"]["adminAuditLogs"]
  end

  it "returns every log when no filter is given" do
    logs = fetch

    expect(logs["metadata"]["totalCount"]).to eq(3)
    expect(logs["collection"].map { |log| log["id"] })
      .to match_array([toggle_on_log.id, org_created_log.id, other_org_log.id])
  end

  it "filters by action" do
    logs = fetch(actions: ["org_created"])

    expect(logs["collection"].map { |log| log["id"] }).to eq([org_created_log.id])
  end

  it "filters by several actions" do
    logs = fetch(actions: %w[org_created toggle_off])

    expect(logs["collection"].map { |log| log["id"] })
      .to match_array([org_created_log.id, other_org_log.id])
  end

  it "filters by actor" do
    logs = fetch(actorUserIds: [admin_user.id])

    expect(logs["collection"].map { |log| log["id"] }).to eq([toggle_on_log.id])
  end

  it "filters by several actors" do
    logs = fetch(actorUserIds: [admin_user.id, other_admin.id])

    expect(logs["metadata"]["totalCount"]).to eq(3)
  end

  it "filters by organization" do
    logs = fetch(organizationIds: [other_organization.id])

    expect(logs["collection"].map { |log| log["id"] }).to eq([other_org_log.id])
  end

  it "filters by several organizations" do
    logs = fetch(organizationIds: [organization.id, other_organization.id])

    expect(logs["metadata"]["totalCount"]).to eq(3)
  end

  it "combines the filters" do
    logs = fetch(actions: %w[org_created toggle_off], organizationIds: [organization.id])

    expect(logs["collection"].map { |log| log["id"] }).to eq([org_created_log.id])
  end

  it "returns the organization name of each log" do
    logs = fetch(organizationIds: [organization.id])

    expect(logs["collection"].map { |log| log["organizationName"] }.uniq).to eq(["ACME Corp"])
  end

  context "when the user is not a CS admin" do
    let(:regular_user) { create(:user, email: "user@acme.test") }

    it "returns an unauthorized error" do
      result = execute_graphql(current_user: regular_user, query:, variables: {})

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `lago exec api bundle exec rspec spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb`

Expected: failures on the argument names. graphql-ruby reports errors such as `Field 'adminAuditLogs' doesn't accept argument 'actions'`, so `result["data"]` is nil and the examples raise `NoMethodError` on nil. Every example querying with the new arguments must fail; the unauthorized example may already pass.

- [ ] **Step 3: Replace the arguments and the filter chain**

In `app/graphql/resolvers/admin/audit_logs_resolver.rb`, replace the argument list and `resolve` body so the file reads:

```ruby
# frozen_string_literal: true

module Resolvers
  module Admin
    class AuditLogsResolver < Resolvers::BaseResolver
      include AuthenticableAdminUser

      description "Query admin audit logs with filters"

      argument :actions, [Types::Admin::ActionEnum], required: false
      argument :actor_user_ids, [ID], required: false
      argument :feature_key, String, required: false
      argument :feature_type, Types::Admin::FeatureTypeEnum, required: false
      argument :from_date, GraphQL::Types::ISO8601Date, required: false
      argument :limit, Integer, required: false
      argument :organization_ids, [ID], required: false
      argument :page, Integer, required: false
      argument :to_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Admin::AuditLogType.collection_type, null: false

      def resolve(**args)
        logs = CsAdminAuditLog.newest_first.includes(:organization)

        logs = logs.where(organization_id: args[:organization_ids]) if args[:organization_ids].present?
        logs = logs.where(actor_user_id: args[:actor_user_ids]) if args[:actor_user_ids].present?
        logs = logs.where(action: args[:actions]) if args[:actions].present?
        logs = logs.where(feature_key: args[:feature_key]) if args[:feature_key]
        logs = logs.where(feature_type: args[:feature_type]) if args[:feature_type]
        logs = logs.where("created_at >= ?", args[:from_date].beginning_of_day) if args[:from_date]
        logs = logs.where("created_at <= ?", args[:to_date].end_of_day) if args[:to_date]

        logs.page(args[:page]).per(args[:limit] || 25)
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `lago exec api bundle exec rspec spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb`

Expected: PASS, 10 examples, 0 failures.

- [ ] **Step 5: Regenerate the GraphQL schema dump**

Run: `lago exec api bundle exec rake graphql:schema:dump`

Then confirm the new signature is in the dump:

Run: `PAGER=cat grep -n "adminAuditLogs" schema.graphql`

Expected: the line shows `actions: [AdminActionEnum!]`, `actorUserIds: [ID!]` and `organizationIds: [ID!]`, and no longer `actorUserId: ID` or `organizationId: ID`.

- [ ] **Step 6: Check nothing unintended changed, then lint**

Run: `PAGER=cat git status --short`

Revert any annotation churn you did not intend, e.g.:

```bash
git checkout -- app/models/metadata/item_metadata.rb
```

Run: `lago exec api bundle exec rubocop app/graphql/resolvers/admin/audit_logs_resolver.rb spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb`

Expected: no offenses.

- [ ] **Step 7: Commit**

```bash
git add app/graphql/resolvers/admin/audit_logs_resolver.rb spec/graphql/resolvers/admin/audit_logs_resolver_spec.rb schema.graphql schema.json
git commit -m "$(cat <<'EOF'
feat(admin): filter audit logs by action and by ids

## Context

The audit log list of the CS admin panel could not be filtered by action,
and accepted a single organization and a single actor at a time, which does
not scale once entries accumulate.

## Description

The audit log query now accepts a list of actions, a list of organizations
and a list of actors, so several values can be selected at once, and each
filter stays optional. Selection is done by id, like every other list filter.

Organizations are also loaded upfront, since exposing the organization name
of an entry previously queried the organization of every returned row.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: CS admin list for the actor filter

**Files:**
- Create: `app/graphql/resolvers/admin/users_resolver.rb`
- Modify: `app/graphql/types/query_type.rb` (admin field block, after `admin_audit_logs`)
- Test: `spec/graphql/resolvers/admin/users_resolver_spec.rb` (create)
- Modify: `schema.graphql`, `schema.json` (regenerated)

**Interfaces:**
- Consumes: `User` (boolean column `cs_admin`), `Types::UserType`, `AuthenticableAdminUser`.
- Produces: the `adminCsAdmins` query, returning `[User!]!` as `Types::UserType`, ordered by email ascending, without pagination.

- [ ] **Step 1: Write the failing spec**

Create `spec/graphql/resolvers/admin/users_resolver_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Admin::UsersResolver do
  let(:query) do
    <<~GQL
      query {
        adminCsAdmins { id email csAdmin }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let!(:other_admin) { create(:user, email: "andy@getlago.com", cs_admin: true) }
  let!(:regular_user) { create(:user, email: "user@acme.test") }

  it "returns the CS admins ordered by email" do
    result = execute_graphql(current_user: admin_user, query:)

    cs_admins = result["data"]["adminCsAdmins"]
    expect(cs_admins.map { |user| user["email"] }).to eq(["andy@getlago.com", "cs@getlago.com"])
    expect(cs_admins.map { |user| user["csAdmin"] }.uniq).to eq([true])
  end

  it "excludes users who are not CS admins" do
    result = execute_graphql(current_user: admin_user, query:)

    ids = result["data"]["adminCsAdmins"].map { |user| user["id"] }
    expect(ids).not_to include(regular_user.id)
  end

  context "when the user is not a CS admin" do
    it "returns an unauthorized error" do
      result = execute_graphql(current_user: regular_user, query:)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `lago exec api bundle exec rspec spec/graphql/resolvers/admin/users_resolver_spec.rb`

Expected: FAIL with `NameError` / `uninitialized constant Resolvers::Admin::UsersResolver`.

- [ ] **Step 3: Create the resolver**

Create `app/graphql/resolvers/admin/users_resolver.rb`:

```ruby
# frozen_string_literal: true

module Resolvers
  module Admin
    class UsersResolver < Resolvers::BaseResolver
      include AuthenticableAdminUser

      description "List CS admin users (admin only)"

      type [Types::UserType], null: false

      def resolve
        User.where(cs_admin: true).order(:email)
      end
    end
  end
end
```

- [ ] **Step 4: Register the query**

In `app/graphql/types/query_type.rb`, add the field right after `admin_audit_logs` so the admin block reads:

```ruby
    field :admin_audit_logs, resolver: Resolvers::Admin::AuditLogsResolver
    field :admin_cs_admins, resolver: Resolvers::Admin::UsersResolver
    field :admin_organization, resolver: Resolvers::Admin::OrganizationResolver
    field :admin_organizations, resolver: Resolvers::Admin::OrganizationsResolver
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `lago exec api bundle exec rspec spec/graphql/resolvers/admin/users_resolver_spec.rb`

Expected: PASS, 3 examples, 0 failures.

- [ ] **Step 6: Regenerate the GraphQL schema dump**

Run: `lago exec api bundle exec rake graphql:schema:dump`

Run: `PAGER=cat grep -n "adminCsAdmins" schema.graphql`

Expected: a line declaring `adminCsAdmins: [User!]!`.

- [ ] **Step 7: Run the whole admin suite, check the tree, lint**

Run: `lago exec api bundle exec rspec spec/graphql/resolvers/admin spec/services/admin spec/requests/admin`

Expected: PASS, 0 failures.

Run: `PAGER=cat git status --short`

Revert any annotation churn you did not intend, e.g.:

```bash
git checkout -- app/models/metadata/item_metadata.rb
```

Run: `lago exec api bundle exec rubocop app/graphql/resolvers/admin/users_resolver.rb app/graphql/types/query_type.rb spec/graphql/resolvers/admin/users_resolver_spec.rb`

Expected: no offenses.

- [ ] **Step 8: Commit**

```bash
git add app/graphql/resolvers/admin/users_resolver.rb app/graphql/types/query_type.rb spec/graphql/resolvers/admin/users_resolver_spec.rb schema.graphql schema.json
git commit -m "$(cat <<'EOF'
feat(admin): expose CS admins for the actor filter

## Context

Filtering audit logs by actor is done by id, so the admin panel needs the
list of candidate actors to populate its filter dropdown.

## Description

A new admin query returns every CS admin, ordered by email, so the dropdown
stays stable regardless of who already acted. The list is small enough not to
need pagination and reuses the existing user type, which already exposes the
id and email the dropdown reads.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Out of Scope

Do not add these, even if they look natural while editing the files:

- A plural `feature_types` filter on the audit log query.
- Free-text search on the reason or on the organization name.
- Cursor-based pagination.
- Filtering the CS admin list, or paginating it.
