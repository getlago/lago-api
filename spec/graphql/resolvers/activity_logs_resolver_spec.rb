# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ActivityLogsResolver, type: :graphql, clickhouse: true do
  let(:required_permission) { "audit_logs:view" }
  let(:query) do
    <<~GQL
      query {
        activityLogs(limit: 5) {
          collection {
            resourceId
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:clickhouse_activity_log) { create(:clickhouse_activity_log) }

  before { clickhouse_activity_log }

  context "when left TODOs in code" do
    it "fails" do
      fail "TODO at Resolvers::ActivityLogsResolver#resolve"
    end
  end
end
