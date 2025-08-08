# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SubscriptionResolver, type: :graphql do
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
          plan {
            id
            code
          }
          nextSubscriptionType
          nextSubscriptionAt
          entitlements { code }
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
      expect(subscription_response["entitlements"]).to eq []
    end
  end

  it "returns a single subscription", :aggregate_failures do
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
      "endingAt" => subscription.ending_at
    )

    expect(subscription_response["plan"]).to include(
      "id" => subscription.plan.id,
      "code" => subscription.plan.code
    )
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

  context "when subscription has entitlements" do
    let(:query) do
      <<~GQL
        query($subscriptionId: ID, $externalId: ID) {
          subscription(id: $subscriptionId, externalId: $externalId) {
            id
            externalId
            name
            startedAt
            endingAt
            plan {
              id
              code
            }
            nextSubscriptionType
            nextSubscriptionAt
            entitlements {
              code
              name
              description
              privileges {
                code
                name
                valueType
                config
                value
                planValue
                overrideValue
              }
            }
          }
        }
      GQL
    end

    let(:feature1) { create(:feature, organization:, code: "feature1", name: "Feature 1", description: "First feature") }
    let(:privilege1) { create(:privilege, feature: feature1, code: "privilege1", name: "Privilege 1", value_type: "boolean") }
    let(:entitlement1) { create(:entitlement, feature: feature1, plan: subscription.plan) }
    let(:entitlement_value1) { create(:entitlement_value, entitlement: entitlement1, privilege: privilege1, value: "true") }

    let(:feature2) { create(:feature, organization:, code: "feature2", name: "Feature 2", description: "Second feature") }
    let(:privilege2) { create(:privilege, feature: feature2, code: "privilege2", name: "Privilege 2", value_type: "string") }
    let(:entitlement2) { create(:entitlement, feature: feature2, plan: subscription.plan) }
    let(:entitlement_value2) { create(:entitlement_value, entitlement: entitlement2, privilege: privilege2, value: "test_value") }

    # Subscription override
    let(:entitlement3) { create(:entitlement, feature: feature2, plan: nil, subscription:) }
    let(:entitlement_value3) { create(:entitlement_value, entitlement: entitlement3, privilege: privilege2, value: "override_value") }

    before do
      entitlement_value1
      entitlement_value2
      entitlement_value3
    end

    it "returns all non-removed entitlements" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          subscriptionId: subscription.id
        }
      )

      entitlements_response = result["data"]["subscription"]["entitlements"]

      expect(entitlements_response).to be_an(Array)
      expect(entitlements_response.size).to eq(2)

      feature1_entitlement = entitlements_response.find { |e| e["code"] == "feature1" }
      expect(feature1_entitlement).to include(
        "code" => "feature1",
        "name" => "Feature 1",
        "description" => "First feature"
      )
      expect(feature1_entitlement["privileges"]).to be_an(Array)
      expect(feature1_entitlement["privileges"].size).to eq(1)
      expect(feature1_entitlement["privileges"].first).to include(
        "code" => "privilege1",
        "name" => "Privilege 1",
        "valueType" => "boolean",
        "value" => "true",
        "planValue" => "true",
        "overrideValue" => nil
      )

      feature2_entitlement = entitlements_response.find { |e| e["code"] == "feature2" }
      expect(feature2_entitlement).to include(
        "code" => "feature2",
        "name" => "Feature 2",
        "description" => "Second feature"
      )
      expect(feature2_entitlement["privileges"]).to be_an(Array)
      expect(feature2_entitlement["privileges"].size).to eq(1)
      expect(feature2_entitlement["privileges"].first).to include(
        "code" => "privilege2",
        "name" => "Privilege 2",
        "valueType" => "string",
        "value" => "override_value",
        "planValue" => "test_value",
        "overrideValue" => "override_value"
      )
    end
  end
end
