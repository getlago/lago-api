# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ActivityLogsResolver, type: :graphql, clickhouse: true do
  let(:required_permission) { "audit_logs:view" }
  let(:filters) { "limit: 5" }
  let(:query) do
    <<~GQL
      query {
        activityLogs(#{filters}) {
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

  it "returns the list of activity logs" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    activity_logs_response = result["data"]["activityLogs"]

    aggregate_failures do
      expect(activity_logs_response["collection"].count).to eq(organization.activity_logs.count)
      expect(activity_logs_response["collection"].first["activityId"]).to eq(clickhouse_activity_log.activity_id)

      expect(activity_logs_response["metadata"]["currentPage"]).to eq(1)
      expect(activity_logs_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "when filtered" do
    context "with logged_at" do
      let(:dated_activity_log) { create(:clickhouse_activity_log, membership:, logged_at: "2025-03-10T09:00:00") }

      before { dated_activity_log }

      context "with fromDate" do
        let(:filters) { 'fromDate: "2025-03-16T15:15:00"' }

        it "returns the filtered list" do
          result = execute_graphql(
            current_user: membership.user,
            current_organization: organization,
            permissions: required_permission,
            query:
          )

          activity_logs_response = result["data"]["activityLogs"]

          aggregate_failures do
            expect(activity_logs_response["collection"].count).to eq(1)
            expect(activity_logs_response["collection"].first["activityId"]).to eq(clickhouse_activity_log.activity_id)
          end
        end
      end

      context "with toDate" do
        let(:filters) { 'toDate: "2025-03-16T15:15:00"' }

        it "returns the filtered list" do
          result = execute_graphql(
            current_user: membership.user,
            current_organization: organization,
            permissions: required_permission,
            query:
          )

          activity_logs_response = result["data"]["activityLogs"]

          aggregate_failures do
            expect(activity_logs_response["collection"].count).to eq(1)
            expect(activity_logs_response["collection"].first["activityId"]).to eq(dated_activity_log.activity_id)
          end
        end
      end
    end

    context "with activity types" do
      let(:special_activity_log) { create(:clickhouse_activity_log, membership:, activity_type: "special") }
      let(:filters) { 'activityTypes: ["special"]' }

      before { special_activity_log }

      it "returns the filtered list" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        activity_logs_response = result["data"]["activityLogs"]

        aggregate_failures do
          expect(activity_logs_response["collection"].count).to eq(1)
          expect(activity_logs_response["collection"].first["activityId"]).to eq(special_activity_log.activity_id)
        end
      end
    end

    context "with activity source" do
      let(:system_activity_log) { create(:clickhouse_activity_log, membership:, activity_source: "system") }
      let(:filters) { "activitySources: [system]" }

      before { system_activity_log }

      it "returns the filtered list" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        activity_logs_response = result["data"]["activityLogs"]

        aggregate_failures do
          expect(activity_logs_response["collection"].count).to eq(1)
          expect(activity_logs_response["collection"].first["activityId"]).to eq(system_activity_log.activity_id)
        end
      end
    end

    context "with user emails" do
      let(:user) { create(:user) }
      let(:other_user_membership) { create(:membership, user: user, organization:) }
      let(:user_activity_log) { create(:clickhouse_activity_log, membership:, user_id: user.id) }
      let(:filters) { "userEmails: [\"#{user.email}\"]" }

      before do
        user_activity_log
        other_user_membership
      end

      it "returns the filtered list" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        activity_logs_response = result["data"]["activityLogs"]

        aggregate_failures do
          expect(activity_logs_response["collection"].count).to eq(1)
          expect(activity_logs_response["collection"].first["activityId"]).to eq(user_activity_log.activity_id)
        end
      end
    end
  end
end
