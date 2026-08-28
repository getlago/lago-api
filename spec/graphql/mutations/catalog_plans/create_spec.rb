# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CatalogPlans::Create do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input:}
    )
  end

  let_it_be(:membership) { create_default(:membership) }
  let(:organization) { membership.organization }
  let(:required_permission) { "plans:create" }
  let(:input) { {name: "Growth", code: "growth", currency: "EUR"} }

  let(:query) do
    <<~GQL
      mutation($input: CreateCatalogPlanInput!) {
        createCatalogPlan(input: $input) { id code amountCurrency }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires permission", "plans:create"

  it "creates a catalog plan" do
    plan_response = result["data"]["createCatalogPlan"]

    expect(plan_response["code"]).to eq("growth")
    expect(plan_response["amountCurrency"]).to eq("EUR")
    expect(Plan.find(plan_response["id"])).to have_attributes(
      pricing_type: "product_catalog", interval: nil, amount_cents: nil
    )
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(result["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
