# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductsQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:) }

  let(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }

  let!(:product_one) { create(:product, organization:, name: "Cards", code: "cards") }
  let!(:product_two) { create(:product, organization:, name: "Storage", code: "storage") }

  it "returns all products of the organization" do
    expect(result.products).to match_array([product_one, product_two])
  end

  it "does not return products from other organizations" do
    create(:product)
    expect(result.products).to match_array([product_one, product_two])
  end

  context "with a search term on name" do
    let(:search_term) { "car" }

    it "returns matching products" do
      expect(result.products).to eq([product_one])
    end
  end

  context "with a search term on code" do
    let(:search_term) { "stor" }

    it "returns matching products" do
      expect(result.products).to eq([product_two])
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
