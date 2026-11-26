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
          collection { id code name currency appliedRateCardsCount contractsCount attachedToContracts }
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

  context "with scoping arguments" do
    let(:rate_card) { create(:rate_card, organization:) }
    let(:variables) { {productIds: [rate_card.product_id]} }
    let(:query) do
      <<~GQL
        query($productIds: [ID!]) {
          catalogPlans(productIds: $productIds) { collection { id } }
        }
      GQL
    end

    before do
      create(:catalog_plan, organization:, code: "scale")
      create(:plan_rate_card, organization:, catalog_plan:, rate_card:)
    end

    it "returns the plans pricing those products" do
      expect(result["data"]["catalogPlans"]["collection"].map { it["id"] }).to eq([catalog_plan.id])
    end
  end

  it "resolves the per-plan counts across the list" do
    create(:catalog_plan, organization:, code: "scale")
    create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:))
    create(:contract, organization:, catalog_plan:)

    collection = result["data"]["catalogPlans"]["collection"].index_by { it["code"] }

    expect(collection["growth"]).to include(
      "appliedRateCardsCount" => 1, "contractsCount" => 1, "attachedToContracts" => true
    )
    expect(collection["scale"]).to include(
      "appliedRateCardsCount" => 0, "contractsCount" => 0, "attachedToContracts" => false
    )
  end

  context "with metadata on several plans" do
    let(:query) do
      <<~GQL
        query {
          catalogPlans(limit: 5) { collection { code #{metadata_selection} } }
        }
      GQL
    end
    let(:metadata_selection) { "metadata { key value }" }

    before do
      create(:item_metadata, owner: catalog_plan, organization:, value: {"tier" => "gold"})
      %w[scale enterprise].each do |code|
        plan = create(:catalog_plan, organization:, code:)
        create(:item_metadata, owner: plan, organization:, value: {"tier" => code})
      end
    end

    it "loads the metadata of every plan in one query" do
      expect(capture_sql { result }.grep(/FROM "item_metadata"/).size).to eq(1)
      expect(result["data"]["catalogPlans"]["collection"].to_h { [it["code"], it["metadata"]] }).to eq(
        "growth" => [{"key" => "tier", "value" => "gold"}],
        "scale" => [{"key" => "tier", "value" => "scale"}],
        "enterprise" => [{"key" => "tier", "value" => "enterprise"}]
      )
    end

    context "when metadata is not selected" do
      let(:metadata_selection) { "" }

      it "does not query the metadata" do
        expect(capture_sql { result }.grep(/"item_metadata"/)).to be_empty
      end
    end
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
