# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ApiLogsResolver, type: :graphql, clickhouse: true do
  let(:required_permission) { "audit_logs:view" }
  let(:query) do
    <<~GQL
      query {
        apiLogs(limit: 5) {
          collection {
            requestId
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:api_log) { create(:clickhouse_api_log, membership:) }

  before { api_log }

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

    it "returns the list of api logs" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      api_logs_response = result["data"]["apiLogs"]

      expect(api_logs_response["collection"].count).to eq(organization.api_logs.count)
      expect(api_logs_response["collection"].first["requestId"]).to eq(api_log.request_id)

      expect(api_logs_response["metadata"]["currentPage"]).to eq(1)
      expect(api_logs_response["metadata"]["totalCount"]).to eq(1)
    end

    context "with graphql filters" do
      context "when httpStatuses" do
        let(:failed_api_log) { create(:clickhouse_api_log, membership:, http_status: 404) }
        let(:query) do
          <<~GQL
            query {
              apiLogs(limit: 5, httpStatuses: [#{http_status}]) {
                collection {
                  requestId
                }
                metadata { currentPage, totalCount }
              }
            }
          GQL
        end

        before { failed_api_log }

        context "with string" do
          let(:http_status) { "failed" }

          it "return failed api logs" do
            result = execute_graphql(
              current_user: membership.user,
              current_organization: organization,
              permissions: required_permission,
              query:
            )

            api_logs_response = result["data"]["apiLogs"]

            expect(api_logs_response["collection"].first["requestId"]).to eq(failed_api_log.request_id)

            expect(api_logs_response["metadata"]["currentPage"]).to eq(1)
            expect(api_logs_response["metadata"]["totalCount"]).to eq(1)
          end
        end

        context "with integer" do
          let(:http_status) { 404 }

          it "return failed api logs" do
            result = execute_graphql(
              current_user: membership.user,
              current_organization: organization,
              permissions: required_permission,
              query:
            )

            api_logs_response = result["data"]["apiLogs"]

            expect(api_logs_response["collection"].first["requestId"]).to eq(failed_api_log.request_id)

            expect(api_logs_response["metadata"]["currentPage"]).to eq(1)
            expect(api_logs_response["metadata"]["totalCount"]).to eq(1)
          end
        end
      end
    end

    context "with query filters" do
      let(:filters) do
        {
          from_date: nil,
          to_date: nil,
          http_methods: nil,
          http_statuses: nil,
          api_version: nil,
          api_key_ids: nil,
          request_ids: nil,
          request_paths: nil
        }
      end

      it "sends all possible filters to query" do
        allow(ApiLogsQuery).to receive(:call).and_call_original

        execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:
        )

        expect(ApiLogsQuery).to have_received(:call).with(
          organization: organization,
          pagination: {limit: 5, page: nil},
          filters:
        )
      end
    end
  end
end
