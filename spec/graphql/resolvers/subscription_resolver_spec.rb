# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SubscriptionResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($subscriptionId: ID!) {
        subscription(id: $subscriptionId) {
          id
          name
          startedAt
          endingAt
          plan {
            id
            code
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  before do
    customer
  end

  it "returns a single subscription", :aggregate_failures do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {subscriptionId: subscription.id}
    )

    subscription_response = result["data"]["subscription"]
    expect(subscription_response).to include(
      "id" => subscription.id,
      "name" => subscription.name,
      "startedAt" => subscription.started_at.iso8601,
      "endingAt" => subscription.ending_at
    )

    expect(subscription_response["plan"]).to include(
      "id" => subscription.plan.id,
      "code" => subscription.plan.code
    )
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {subscriptionId: subscription.id}
      )

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when subscription is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {subscriptionId: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
