# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemsQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:product) { create(:product, organization:) }
  let!(:usage_item) { create(:product_item, organization:, product:, name: "Storage", code: "storage") }
  let!(:fixed_item) { create(:product_item, :fixed, :standalone, organization:, name: "Seats", code: "seats") }

  it "returns all product items of the organization" do
    expect(result.product_items).to match_array([usage_item, fixed_item])
  end

  it "does not return product items from other organizations" do
    create(:product_item)
    expect(result.product_items).to match_array([usage_item, fixed_item])
  end

  context "with a product filter" do
    let(:filters) { {product_id: product.id} }

    it "returns only the items of that product" do
      expect(result.product_items).to eq([usage_item])
    end
  end

  context "with an item_types filter" do
    let(:filters) { {item_types: %w[fixed]} }

    it "returns only items of those types" do
      expect(result.product_items).to eq([fixed_item])
    end
  end

  context "with a search term" do
    let(:search_term) { "sea" }

    it "returns matching items" do
      expect(result.product_items).to eq([fixed_item])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.product_items.count).to eq(1)
      expect(result.product_items.total_count).to eq(2)
    end
  end
end
