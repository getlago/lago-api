# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFiltersQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:product) { create(:product, organization:) }
  let!(:filter_one) { create(:product_filter, organization:, product:, name: "US cards", code: "us_cards") }
  let!(:filter_two) { create(:product_filter, organization:, name: "EU cards", code: "eu_cards") }

  it "returns all filters of the organization" do
    expect(result.product_filters).to match_array([filter_one, filter_two])
  end

  it "does not return filters from other organizations" do
    create(:product_filter)
    expect(result.product_filters).to match_array([filter_one, filter_two])
  end

  context "with a product filter" do
    let(:filters) { {product_id: product.id} }

    it "returns only the filters of that product" do
      expect(result.product_filters).to eq([filter_one])
    end
  end

  context "with a product_category filter" do
    let(:filters) { {product_category_ids: [product.product_category_id]} }

    it "returns only the filters of items belonging to those product_categories" do
      expect(result.product_filters).to eq([filter_one])
    end
  end

  context "with a without_product_category filter" do
    let(:standalone_item) { create(:product, :standalone, organization:) }
    let!(:orphan_filter) { create(:product_filter, organization:, product: standalone_item) }
    let(:filters) { {without_product_category: true} }

    it "returns only the filters of items not attached to any product_category" do
      expect(result.product_filters).to eq([orphan_filter])
    end
  end

  context "with product_category and without_product_category filters combined" do
    let(:standalone_item) { create(:product, :standalone, organization:) }
    let!(:orphan_filter) { create(:product_filter, organization:, product: standalone_item) }
    let(:filters) { {product_category_ids: [product.product_category_id], without_product_category: true} }

    it "returns the union of both" do
      expect(result.product_filters).to match_array([filter_one, orphan_filter])
    end
  end

  context "with a search term on name" do
    let(:search_term) { "US" }

    it "returns matching filters" do
      expect(result.product_filters).to eq([filter_one])
    end
  end

  context "with a search term on code" do
    let(:search_term) { "eu_" }

    it "returns matching filters" do
      expect(result.product_filters).to eq([filter_two])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.product_filters.count).to eq(1)
      expect(result.product_filters.total_count).to eq(2)
    end
  end
end
