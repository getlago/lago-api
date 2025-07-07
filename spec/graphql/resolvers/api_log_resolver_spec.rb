# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ApiLogResolver, type: :graphql, clickhouse: true do
  let(:required_permission) { "audit_logs:view" }
  let(:query) do
    <<~GQL
      query($requestId: ID!) {
        apiLog(requestId: $requestId) {
          requestId
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:clickhouse_api_log) { create(:clickhouse_api_log, membership:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "audit_logs:view"

  shared_examples "unauthorized error" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {requestId: clickhouse_api_log.request_id}
      )

      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "without premium feature" do
    it_behaves_like "unauthorized error"
  end

  context "without database configuration" do
    around { |test| lago_premium!(&test) }

    before do
      ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
      ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = nil
      ENV["LAGO_CLICKHOUSE_ENABLED"] = nil
    end

    it_behaves_like "unauthorized error"
  end

  context "with premium feature" do
    around { |test| lago_premium!(&test) }

    it "returns a single api log" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {requestId: clickhouse_api_log.request_id}
      )

      api_log_response = result["data"]["apiLog"]
      expect(api_log_response["requestId"]).to eq(clickhouse_api_log.request_id)
    end

    context "when activity log is not found" do
      it "returns an error" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {requestId: "invalid"}
        )

        expect_graphql_error(result:, message: "Resource not found")
      end
    end
  end
end
