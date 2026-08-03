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
