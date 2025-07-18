# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Entitlement::SubscriptionEntitlementsResolver, type: :graphql do
  subject { execute_query(query:) }

  let(:organization) { create(:organization) }
  let(:subscription_external_id) { "sub_123" }
  let(:required_permission) { "subscriptions:view" }
  let(:query) do
    <<~GQL
      query {
        subscriptionEntitlements(subscriptionExternalId: "#{subscription_external_id}") {
          code
          removed
          privileges {
            code
            value
          }
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:view"
  it_behaves_like "requires Premium license"

  it do
    expect(described_class).to accept_argument(:subscription_external_id).of_type("String!")
  end

  it "returns subscription entitlements and removed features" do
    feature1 = create(:feature, organization:)
    feature2 = create(:feature, organization:)
    _feature3 = create(:feature, organization:)

    # Create an entitlement for the subscription
    entitlement = create(:entitlement, organization:, feature: feature1, subscription_external_id:)
    entitlement_value = create(:entitlement_value, entitlement:, privilege: create(:privilege, feature: feature1))

    # Create a removed feature for the subscription
    create(:subscription_feature_removal, organization:, feature: feature2, subscription_external_id:)

    result = subject

    subscription_entitlements = result["data"]["subscriptionEntitlements"]
    expect(subscription_entitlements.count).to eq(2)

    # Check regular entitlement
    regular_entitlement = subscription_entitlements.find { |e| e["code"] == feature1.code }
    expect(regular_entitlement["removed"]).to be(false)
    expect(regular_entitlement["privileges"]).to eq([
      {"code" => entitlement_value.privilege.code, "value" => entitlement_value.value}
    ])

    # Check removed feature
    removed_entitlement = subscription_entitlements.find { |e| e["code"] == feature2.code }
    expect(removed_entitlement["removed"]).to be(true)
    expect(removed_entitlement["privileges"]).to be_empty
  end

  it "returns only entitlements for the specified subscription" do
    feature1 = create(:feature, organization:)
    feature2 = create(:feature, organization:)
    other_subscription_id = "sub_456"

    # Create entitlements for different subscriptions
    create(:entitlement, organization:, feature: feature1, subscription_external_id:)
    create(:entitlement, organization:, feature: feature2, subscription_external_id: other_subscription_id)

    result = subject

    subscription_entitlements = result["data"]["subscriptionEntitlements"]
    expect(subscription_entitlements.count).to eq(1)
    expect(subscription_entitlements.first["code"]).to eq(feature1.code)
  end

  it "returns only removed features for the specified subscription" do
    feature1 = create(:feature, organization:)
    feature2 = create(:feature, organization:)
    other_subscription_id = "sub_456"

    # Create removed features for different subscriptions
    create(:subscription_feature_removal, organization:, feature: feature1, subscription_external_id:)
    create(:subscription_feature_removal, organization:, feature: feature2, subscription_external_id: other_subscription_id)

    result = subject

    subscription_entitlements = result["data"]["subscriptionEntitlements"]
    expect(subscription_entitlements.count).to eq(1)
    expect(subscription_entitlements.first["code"]).to eq(feature1.code)
    expect(subscription_entitlements.first["removed"]).to be(true)
  end

  it "returns empty array when no entitlements or removed features exist" do
    result = subject

    subscription_entitlements = result["data"]["subscriptionEntitlements"]
    expect(subscription_entitlements).to be_empty
  end
end
