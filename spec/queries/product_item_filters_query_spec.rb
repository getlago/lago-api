# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFiltersQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:product_item) { create(:product_item, organization:) }
  let!(:filter_one) { create(:product_item_filter, organization:, product_item:, name: "US cards", code: "us_cards") }
  let!(:filter_two) { create(:product_item_filter, organization:, name: "EU cards", code: "eu_cards") }

  it "returns all filters of the organization" do
    expect(result.product_item_filters).to match_array([filter_one, filter_two])
  end

  it "does not return filters from other organizations" do
    create(:product_item_filter)
    expect(result.product_item_filters).to match_array([filter_one, filter_two])
  end

  context "with a product_item filter" do
    let(:filters) { {product_item_id: product_item.id} }

    it "returns only the filters of that product item" do
      expect(result.product_item_filters).to eq([filter_one])
    end
  end

  context "with a search term on name" do
    let(:search_term) { "US" }

    it "returns matching filters" do
      expect(result.product_item_filters).to eq([filter_one])
    end
  end

  context "with a search term on code" do
    let(:search_term) { "eu_" }

    it "returns matching filters" do
      expect(result.product_item_filters).to eq([filter_two])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.product_item_filters.count).to eq(1)
      expect(result.product_item_filters.total_count).to eq(2)
    end
  end
end
