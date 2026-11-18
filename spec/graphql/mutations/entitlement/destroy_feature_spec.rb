# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Entitlement::DestroyFeature, :premium do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "features:delete" }
  let(:feature) { create(:feature, organization:) }
  let(:input) { {id: feature.id} }
  let(:query) do
    <<-GQL
      mutation($input: DestroyFeatureInput!) {
        destroyFeature(input: $input) {
          id
          code
          name
          description
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "features:delete"

  it "destroys a feature" do
    expect { feature }.to change(Entitlement::Feature, :count).by(1)

    result = subject

    result_data = result["data"]["destroyFeature"]

    expect(result_data["id"]).to eq(feature.id)
    expect(result_data["code"]).to eq(feature.code)
    expect(result_data["name"]).to eq(feature.name)
    expect(result_data["description"]).to eq(feature.description)
  end

  context "when the feature has contract removals" do
    let(:privilege) { create(:privilege, feature:) }
    let(:contract) { create(:contract, organization:) }
    let(:feature_removal) { create(:subscription_feature_removal, :contract, contract:, feature:) }
    let(:privilege_removal) { create(:subscription_feature_removal, :contract, contract:, privilege:) }
    let(:other_feature_removal) { create(:subscription_feature_removal, :contract, contract:, feature: create(:feature, organization:)) }

    before do
      feature_removal
      privilege_removal
      other_feature_removal
    end

    it "discards the contract removals of the feature and of its privileges" do
      result = subject

      expect(result["errors"]).to be_nil
      expect(Entitlement::SubscriptionFeatureRemoval.where(contract:)).to eq([other_feature_removal])
    end
  end

  context "when feature does not exist" do
    let(:input) { {id: "non-existent-id"} }

    it "returns not found error for non-existent feature" do
      result = subject

      expect(result["errors"]).to be_present
    end
  end
end
