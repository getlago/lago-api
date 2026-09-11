# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RateCardsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "rate_cards:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }

  let(:query) do
    <<~GQL
      query($searchTerm: String, $productIds: [ID!], $productCategoryIds: [ID!], $withoutProductCategory: Boolean) {
        rateCards(limit: 5, searchTerm: $searchTerm, productIds: $productIds, productCategoryIds: $productCategoryIds, withoutProductCategory: $withoutProductCategory) {
          collection { id name code currency }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product_category) { create(:product_category, organization:) }
  let(:product) { create(:product, organization:, product_category:) }
  let!(:card_one) { create(:rate_card, organization:, product:, name: "Growth USD", code: "growth_usd") }
  let!(:card_two) { create(:rate_card, organization:, name: "Standard EUR", code: "standard_eur") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns the rate cards of the organization" do
    response = execution["data"]["rateCards"]

    expect(response["collection"].map { it["id"] }).to match_array([card_one.id, card_two.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with a productIds filter" do
    let(:variables) { {productIds: [product.id]} }

    it "returns only the cards of those items" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end

  context "with a productCategoryIds filter" do
    let(:variables) { {productCategoryIds: [product_category.id]} }

    it "returns only the cards of products in that category" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end

  context "with a withoutProductCategory filter" do
    # card_one and card_two are on products that each carry a category.
    let!(:standalone_card) { create(:rate_card, organization:, product: create(:product, :standalone, organization:), code: "standalone") }
    let(:variables) { {withoutProductCategory: true} }

    it "returns only the cards of uncategorized products" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([standalone_card.id])
    end
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "growth"} }

    it "returns matching cards" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end
end
