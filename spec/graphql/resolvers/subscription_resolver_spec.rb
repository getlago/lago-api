# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SubscriptionResolver do
  let(:required_permission) { "subscriptions:view" }
  let(:query) do
    <<~GQL
      query($subscriptionId: ID, $externalId: ID) {
        subscription(id: $subscriptionId, externalId: $externalId) {
          id
          externalId
          name
          startedAt
          endingAt
          progressiveBillingDisabled
          plan {
            id
            code
          }
          nextSubscriptionType
          nextSubscriptionAt
          usageThresholds { amountCents thresholdDisplayName recurring }
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

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:view"

  context "when id and external_id are not provided" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect_graphql_error(
        result:,
        message: "You must provide either `id` or `external_id`."
      )
    end
  end

  context "when external_id is provided" do
    it "returns a single subscription" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          externalId: subscription.external_id
        }
      )

      subscription_response = result["data"]["subscription"]
      expect(subscription_response["id"]).to eq(subscription.id)
      expect(subscription_response["externalId"]).to eq(subscription.external_id)
      expect(subscription_response["usageThresholds"]).to be_an(Array).and be_empty
    end
  end

  it "returns a single subscription" do
    threshold = create(:usage_threshold, :for_subscription, subscription:, amount_cents: 99_00)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {subscriptionId: subscription.id}
    )

    subscription_response = result["data"]["subscription"]
    expect(subscription_response).to include(
      "id" => subscription.id,
      "name" => subscription.name,
      "startedAt" => subscription.started_at.iso8601,
      "endingAt" => subscription.ending_at,
      "progressiveBillingDisabled" => false
    )

    expect(subscription_response["plan"]).to include(
      "id" => subscription.plan.id,
      "code" => subscription.plan.code
    )

    expect(subscription_response["usageThresholds"]).to contain_exactly({
      "amountCents" => "9900",
      "thresholdDisplayName" => threshold.threshold_display_name,
      "recurring" => false
    })
  end

  context "when subscription is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {subscriptionId: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when subscription was upgraded" do
    let(:subscription) { create(:subscription, :terminated, customer:, next_subscriptions: [next_subscription], terminated_at: 1.day.ago, external_id: next_subscription.external_id) }
    let(:next_subscription) { create(:subscription, customer: customer, plan: create(:plan, amount_cents: 33000_00)) }

    it do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {subscriptionId: subscription.id}
      )

      subscription_response = result["data"]["subscription"]
      expect(subscription_response["nextSubscriptionType"]).to eq "upgrade"
      expect(subscription_response["nextSubscriptionAt"]).to be_present
    end
  end
end
