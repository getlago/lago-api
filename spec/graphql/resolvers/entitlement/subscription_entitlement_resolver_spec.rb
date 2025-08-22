# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Entitlement::SubscriptionEntitlementResolver, type: :graphql do
  subject { execute_query(query:, variables:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, plan:) }
  let(:required_permission) { "subscriptions:view" }
  let(:query) do
    <<~GQL
      query($subscriptionId: ID!, $featureCode: String!) {
        subscriptionEntitlement(subscriptionId: $subscriptionId, featureCode: $featureCode) {
          code
          name
          description
          privileges {
            code
            name
            valueType
            value
            config { selectOptions }
          }
        }
      }
    GQL
  end

  let(:feature) { create(:feature, code: "seats", organization:) }
  let(:privilege) { create(:privilege, feature: feature, code: "max", value_type: "integer") }

  let(:variables) { {subscriptionId: subscription.id, featureCode: feature.code} }

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:view"
  it_behaves_like "requires Premium license"

  it do
    expect(described_class).to accept_argument(:subscription_id).of_type("ID!")
    expect(described_class).to accept_argument(:feature_code).of_type("String!")
  end

  context "when subscription has no features" do
    it "returns an error" do
      expect_graphql_error(result: subject, message: "Resource not found")
    end
  end

  context "when subscription has features" do
    before do
      entitlement = create(:entitlement, feature:, plan:)
      create(:entitlement_value, entitlement:, privilege:, value: 10)
    end

    it "returns the entitlement" do
      result = subject
      data = result["data"]["subscriptionEntitlement"]

      expect(data).to eq({
        "code" => "seats",
        "name" => "Feature Name",
        "description" => "Feature Description",
        "privileges" => [
          {
            "code" => "max",
            "name" => nil,
            "valueType" => "integer",
            "value" => "10",
            "config" => {
              "selectOptions" => nil
            }
          }
        ]
      })
    end

    context "when requesting a feature not on the subscription" do
      let(:other_feature) { create(:feature, code: "new", organization:) }
      let(:variables) { {subscriptionId: subscription.id, featureCode: other_feature.code} }

      it "returns an error" do
        expect_graphql_error(result: subject, message: "Resource not found")
      end
    end
  end
end
