# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RealtimeUsage::EventsResolver, clickhouse: {clean_before: true}, transaction: false do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($externalCustomerId: String, $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime) {
        realtimeUsageEvents(externalCustomerId: $externalCustomerId, fromDatetime: $fromDatetime, toDatetime: $toDatetime) {
          fromDatetime toDatetime timezone timeGranularity lastIngestedAt eventsCount
          points { time eventsCount }
        }
      }
    GQL
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:variables) { {fromDatetime: "2026-08-24T09:00:00Z", toDatetime: "2026-08-24T11:00:00Z"} }

  include_context "with realtime usage availability"

  before do
    create(:clickhouse_usage_bucket, subscription:, customer:, organization:, bucket: Time.zone.parse("2026-08-24 10:15:00"),
      events_count: 5, last_ingested_at: Time.zone.parse("2026-08-24 10:16:00"))
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  it "returns the events of every period" do
    result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

    expect(result["data"]["realtimeUsageEvents"]).to eq(
      "fromDatetime" => "2026-08-24T09:00:00Z",
      "toDatetime" => "2026-08-24T11:00:00Z",
      "timezone" => "TZ_UTC",
      "timeGranularity" => "hour",
      "lastIngestedAt" => "2026-08-24T10:16:00Z",
      "eventsCount" => "5",
      "points" => [{"time" => "2026-08-24T09:00:00Z", "eventsCount" => "0"}, {"time" => "2026-08-24T10:00:00Z", "eventsCount" => "5"}]
    )
  end

  context "with the external id of a customer" do
    let(:variables) { super().merge(externalCustomerId: customer.external_id) }

    before do
      other_subscription = create(:subscription, customer: create(:customer, organization:))
      create(:clickhouse_usage_bucket, subscription: other_subscription, customer: other_subscription.customer, organization:,
        bucket: Time.zone.parse("2026-08-24 10:15:00"), events_count: 8)
    end

    it "only counts its events" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect(result["data"]["realtimeUsageEvents"]["eventsCount"]).to eq("5")
    end
  end

  context "with the external id of another organization's customer" do
    let(:other_customer) { create(:customer, external_id: customer.external_id) }
    let(:variables) { super().merge(externalCustomerId: other_customer.external_id) }

    before do
      other_subscription = create(:subscription, customer: other_customer)
      create(:clickhouse_usage_bucket, subscription: other_subscription, customer: other_customer, organization:,
        bucket: Time.zone.parse("2026-08-24 10:15:00"), events_count: 8)
    end

    it "does not reach its usage" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect(result["data"]["realtimeUsageEvents"]["eventsCount"]).to eq("5")
    end
  end

  context "when real-time usage is not enabled for the organization" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "returns a forbidden error" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect_forbidden_error(result)
    end
  end
end
