# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SecurityLogResolver do
  let(:query) do
    <<~GQL
      query($logId: ID!) {
        securityLog(logId: $logId) {
          logId
        }
      }
    GQL
  end
  let(:variables) { {logId: "test-id"} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  before { organization.update!(premium_integrations: ["security_logs"]) }

  include_context "with clickhouse availability"

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "security_logs:view"

  context "without premium license" do
    it "returns feature_unavailable error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "security_logs:view",
        query:,
        variables:
      )

      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "when clickhouse is not available", :premium do
    let(:clickhouse_enabled) { nil }

    it "returns feature_unavailable error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "security_logs:view",
        query:,
        variables:
      )

      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "when security_logs is not enabled", :premium do
    before { organization.update!(premium_integrations: []) }

    it "returns feature_unavailable error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "security_logs:view",
        query:,
        variables:
      )

      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "when all conditions are met but the log is absent", :premium do
    it "returns not_found error (stub)" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "security_logs:view",
        query:,
        variables:
      )

      expect_graphql_error(result:, message: "not_found")
    end
  end
end
