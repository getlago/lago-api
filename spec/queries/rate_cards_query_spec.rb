# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardsQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:product_item) { create(:product_item, organization:) }
  let!(:card_one) { create(:rate_card, organization:, product_item:, name: "Growth USD", code: "growth_usd") }
  let!(:card_two) { create(:rate_card, organization:, name: "Standard EUR", code: "standard_eur") }

  it "returns all rate cards of the organization" do
    expect(result.rate_cards).to match_array([card_one, card_two])
  end

  it "does not return rate cards from other organizations" do
    create(:rate_card)
    expect(result.rate_cards).to match_array([card_one, card_two])
  end

  context "with a product_item filter" do
    let(:filters) { {product_item_id: product_item.id} }

    it "returns only the cards of that product item" do
      expect(result.rate_cards).to eq([card_one])
    end
  end

  context "with a search term" do
    let(:search_term) { "growth" }

    it "returns matching cards" do
      expect(result.rate_cards).to eq([card_one])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.rate_cards.count).to eq(1)
      expect(result.rate_cards.total_count).to eq(2)
    end
  end
end
