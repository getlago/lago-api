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
      query($searchTerm: String, $productItemId: ID) {
        rateCards(limit: 5, searchTerm: $searchTerm, productItemId: $productItemId) {
          collection { id name code currency }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product_item) { create(:product_item, organization:) }
  let!(:card_one) { create(:rate_card, organization:, product_item:, name: "Growth USD", code: "growth_usd") }
  let!(:card_two) { create(:rate_card, organization:, name: "Standard EUR", code: "standard_eur") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns the rate cards of the organization" do
    response = execution["data"]["rateCards"]

    expect(response["collection"].map { it["id"] }).to match_array([card_one.id, card_two.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with a product item filter" do
    let(:variables) { {productItemId: product_item.id} }

    it "returns only the cards of that item" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "growth"} }

    it "returns matching cards" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end
end
