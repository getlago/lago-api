# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CatalogPlansResolver do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "plans:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }
  let!(:catalog_plan) { create(:catalog_plan, organization:, name: "Growth", code: "growth", currency: "EUR") }

  let(:query) do
    <<~GQL
      query($searchTerm: String) {
        catalogPlans(limit: 5, searchTerm: $searchTerm) {
          collection { id code name currency }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns the organization catalog plans" do
    create(:catalog_plan)

    collection = result["data"]["catalogPlans"]["collection"]

    expect(collection.map { it["id"] }).to eq([catalog_plan.id])
    expect(collection.first).to include("code" => "growth", "name" => "Growth", "currency" => "EUR")
    expect(result["data"]["catalogPlans"]["metadata"]["totalCount"]).to eq(1)
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "grow"} }

    before { create(:catalog_plan, organization:, name: "Other", code: "other") }

    it "filters by name or code" do
      collection = result["data"]["catalogPlans"]["collection"]

      expect(collection.map { it["id"] }).to eq([catalog_plan.id])
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(result["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
