# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CatalogPlanResolver do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {catalogPlanId: catalog_plan.id}
    )
  end

  let(:required_permission) { "plans:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:catalog_plan) { create(:catalog_plan, organization:, name: "Growth", code: "growth", currency: "EUR") }

  let(:query) do
    <<~GQL
      query($catalogPlanId: ID!) {
        catalogPlan(id: $catalogPlanId) {
          id code name currency
        }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns the catalog plan" do
    expect(result["data"]["catalogPlan"]).to include(
      "id" => catalog_plan.id,
      "code" => "growth",
      "name" => "Growth",
      "currency" => "EUR"
    )
  end

  context "when the catalog plan belongs to another organization" do
    let(:catalog_plan) { create(:catalog_plan) }

    it "returns a not found error" do
      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(result["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
