# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Subscriptions::Update, type: :graphql do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "subscriptions:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      subscription_at: Time.current + 3.days
    )
  end

  let(:query) do
    <<~GQL
      mutation($input: UpdateSubscriptionInput!) {
        updateSubscription(input: $input) {
          id
          name
          subscriptionAt
          entitlements {
            code
            privileges { code planValue overrideValue value }
          }
        }
      }
    GQL
  end
  let(:input) do
    {
      id: subscription.id,
      name: "New name"
    }
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "subscriptions:update"

  it "updates an subscription" do
    result = subject

    result_data = result["data"]["updateSubscription"]

    expect(result_data["name"]).to eq("New name")
    expect(result_data["entitlements"]).to eq []
  end

  context "when subscription has entitlement" do
    let(:feature) { create(:feature, organization:, code: "seats") }
    let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }

    let(:feature2) { create(:feature, code: "storage", organization:) }
    let(:privilege2) { create(:privilege, feature: feature2, code: "limit", value_type: "integer") }
    let(:privilege3) { create(:privilege, feature: feature2, code: "allow_overage", value_type: "boolean") }
    let(:entitlement) { create(:entitlement, feature:, plan: subscription.plan) }
    let(:entitlement_value2) { create(:entitlement_value, entitlement:, privilege: privilege2, value: "100") }
    let(:entitlement_value3) { create(:entitlement_value, entitlement:, privilege: privilege3, value: true) }

    let(:input) do
      {
        id: subscription.id,
        name: "New name",
        entitlements: [
          {featureCode: feature.code, privileges: [
            {privilegeCode: privilege.code, value: "45"}
          ]},
          {featureCode: feature2.code, privileges: [
            {privilegeCode: privilege2.code, value: "444"},
            {privilegeCode: privilege3.code, value: "false"}
          ]}
        ]
      }
    end

    before do
      privilege
      entitlement_value2
      entitlement_value3
    end

    it "updates the subscription and it's entitlements" do
      result = subject

      result_data = result["data"]["updateSubscription"]
      expect(result_data["name"]).to eq("New name")
      expect(result_data["entitlements"].size).to eq(2)
    end
  end
end
