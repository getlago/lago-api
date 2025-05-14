# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::EventResolver, type: :graphql, transaction: false do
  let(:query) do
    <<~GQL
      query($eventId: ID!) {
        event(id: $eventId) {
          id
          code
          transactionId
          externalSubscriptionId
          timestamp
          receivedAt
          customerTimezone
          ipAddress
          apiClient
          payload
          billableMetricName
          matchBillableMetric
          matchCustomField
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:event) do
    create(
      :event,
      code: billable_metric.code,
      organization:,
      external_subscription_id: subscription.external_id,
      timestamp: 2.days.ago,
      properties: {foo_bar: 1234},
      metadata: {user_agent: "Lago Ruby v0.0.1", ip_address: "182.11.32.11"}
    )
  end

  before { event }

  it "returns a single event" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {eventId: event.id}
    )

    event_response = result["data"]["event"]
    aggregate_failures do
      expect(event_response["id"]).to eq(event.id)
      expect(event_response["code"]).to eq(event.code)
    end
  end

  context "when event is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {eventId: "non_existing"}
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end
end
