# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCategoriesQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }

  let!(:product_category_one) { create(:product_category, organization:, name: "Cards", code: "cards") }
  let!(:product_category_two) { create(:product_category, organization:, name: "Storage", code: "storage") }

  it "returns all product_categories of the organization" do
    expect(result.product_categories).to match_array([product_category_one, product_category_two])
  end

  it "does not return product_categories from other organizations" do
    create(:product_category)
    expect(result.product_categories).to match_array([product_category_one, product_category_two])
  end

  context "with a search term on name" do
    let(:search_term) { "car" }

    it "returns matching product_categories" do
      expect(result.product_categories).to eq([product_category_one])
    end
  end

  context "with a search term on code" do
    let(:search_term) { "stor" }

    it "returns matching product_categories" do
      expect(result.product_categories).to eq([product_category_two])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.product_categories.count).to eq(1)
      expect(result.product_categories.total_count).to eq(2)
    end
  end
end
