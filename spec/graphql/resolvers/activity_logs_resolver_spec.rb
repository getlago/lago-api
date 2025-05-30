# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ActivityLogsResolver, type: :graphql, clickhouse: true do
  let(:required_permission) { "audit_logs:view" }
  let(:query) do
    <<~GQL
      query {
        activityLogs(limit: 5) {
          collection {
            activityId
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:clickhouse_activity_log) { create(:clickhouse_activity_log, membership:) }

  before { clickhouse_activity_log }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "audit_logs:view"

  context "without premium feature" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "with premium feature" do
    around { |test| lago_premium!(&test) }

    it "returns the list of activity logs" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      activity_logs_response = result["data"]["activityLogs"]

      expect(activity_logs_response["collection"].count).to eq(organization.activity_logs.count)
      expect(activity_logs_response["collection"].first["activityId"]).to eq(clickhouse_activity_log.activity_id)

      expect(activity_logs_response["metadata"]["currentPage"]).to eq(1)
      expect(activity_logs_response["metadata"]["totalCount"]).to eq(1)
    end

    context "with filters" do
      let(:filters) do
        {
          from_date: nil,
          to_date: nil,
          api_key_ids: nil,
          activity_ids: nil,
          activity_types: nil,
          activity_sources: nil,
          user_emails: nil,
          external_customer_id: nil,
          external_subscription_id: nil,
          resource_ids: nil,
          resource_types: nil
        }
      end

      it "sends all possible filters to query" do
        allow(ActivityLogsQuery).to receive(:call).and_call_original

        execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        expect(ActivityLogsQuery).to have_received(:call).with(
          organization: organization,
          pagination: {limit: 5, page: nil},
          filters:
        )
      end
    end
  end
end
