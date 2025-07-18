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

  context "when subscriptions has entitlements" do
    let(:query) do
      <<~GQL
        query($subscriptionId: ID, $externalId: ID) {
          subscription(id: $subscriptionId, externalId: $externalId) {
            id
            externalId
            entitlements {
              code
              name
              description
              privileges {
                code
                name
                valueType
                value
                planValue
                overrideValue
              }
            }
          }
        }
      GQL
    end

    let(:plan) { subscription.plan }
    let(:feature) { create(:feature, organization:, code: "seats") }
    let(:privilege11) { create(:privilege, feature:, code: "max") }
    let(:privilege12) { create(:privilege, feature:, code: "max_admins") }
    let(:entitlement) { create(:entitlement, plan:, feature: feature) }
    let(:entitlement_value11) { create(:entitlement_value, entitlement: entitlement, privilege: privilege11, value: "100") }
    let(:entitlement_value12) { create(:entitlement_value, entitlement: entitlement, privilege: privilege12, value: "5") }
    let(:entitlement_override) { create(:entitlement, subscription:, plan: nil, feature: feature) }
    let(:entitlement_value_override12) { create(:entitlement_value, entitlement: entitlement_override, privilege: privilege12, value: "12") }

    let(:feature2) { create(:feature, organization:, code: "storage") }
    let(:entitlement2) { create(:entitlement, plan:, feature: feature2) }

    let(:feature3) { create(:feature, organization:, code: "api") }
    let(:entitlement3) { create(:entitlement, subscription:, plan: nil, feature: feature3) }

    let(:feature4) { create(:feature, organization:, code: "mcp") }
    let(:entitlement4) { create(:entitlement, plan:, feature: feature4) }
    let(:entitlement_removal) { create(:subscription_feature_removal, feature: feature4, subscription:) }

    before do
      entitlement_value11
      entitlement_value12
      entitlement_value_override12
      entitlement2
      entitlement3
      entitlement4
      entitlement_removal
    end

    it "returns all entitlements" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          externalId: subscription.external_id
        }
      )

      ent = result["data"]["subscription"]["entitlements"]
      expect(ent.map { it["code"] }).to match_array(%w[seats storage api])
      expect(ent.find { it["code"] == "seats" }["privileges"]).to contain_exactly({
        "code" => "max",
        "name" => nil,
        "valueType" => "string",
        "value" => "100",
        "planValue" => "100",
        "overrideValue" => nil
      }, {
        "code" => "max_admins",
        "name" => nil,
        "valueType" => "string",
        "value" => "12",
        "planValue" => "5",
        "overrideValue" => "12"
      })
    end
  end
end
