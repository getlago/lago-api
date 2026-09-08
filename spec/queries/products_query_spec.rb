# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductsQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:product_category) { create(:product_category, organization:) }
  let!(:usage_item) { create(:product, organization:, product_category:, name: "Storage", code: "storage") }
  let!(:fixed_item) { create(:product, :fixed, :standalone, organization:, name: "Seats", code: "seats") }

  it "returns all products of the organization" do
    expect(result.products).to match_array([usage_item, fixed_item])
  end

  it "does not return products from other organizations" do
    create(:product)
    expect(result.products).to match_array([usage_item, fixed_item])
  end

  context "with a product_category filter" do
    let(:filters) { {product_category_ids: [product_category.id]} }

    it "returns only the items of those product_categories" do
      expect(result.products).to eq([usage_item])
    end
  end

  context "with a without_product_category filter" do
    let(:filters) { {without_product_category: true} }

    it "returns only the items not attached to any product_category" do
      expect(result.products).to eq([fixed_item])
    end
  end

  context "with product_category and without_product_category filters combined" do
    let(:filters) { {product_category_ids: [product_category.id], without_product_category: true} }

    it "returns the union of both" do
      expect(result.products).to match_array([usage_item, fixed_item])
    end
  end

  context "with an product_type filter" do
    let(:filters) { {product_type: "fixed"} }

    it "returns only items of that type" do
      expect(result.products).to eq([fixed_item])
    end
  end

  context "with a search term" do
    let(:search_term) { "sea" }

    it "returns matching items" do
      expect(result.products).to eq([fixed_item])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.products.count).to eq(1)
      expect(result.products.total_count).to eq(2)
    end
  end
end
