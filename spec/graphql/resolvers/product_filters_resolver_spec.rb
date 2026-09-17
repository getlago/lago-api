# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductFiltersResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "product_filters:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }

  let(:query) do
    <<~GQL
      query($searchTerm: String, $productId: ID, $productCategoryIds: [ID!], $withoutProductCategory: Boolean) {
        productFilters(limit: 5, searchTerm: $searchTerm, productId: $productId, productCategoryIds: $productCategoryIds, withoutProductCategory: $withoutProductCategory) {
          collection { id name code }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product) { create(:product, organization:) }
  let!(:filter_one) { create(:product_filter, organization:, product:, name: "US cards") }
  let!(:filter_two) { create(:product_filter, organization:, name: "EU cards") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_filters:view"

  it "returns the filters of the organization" do
    response = execution["data"]["productFilters"]

    expect(response["collection"].map { it["id"] }).to match_array([filter_one.id, filter_two.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with a product filter" do
    let(:variables) { {productId: product.id} }

    it "returns only the filters of that item" do
      expect(execution["data"]["productFilters"]["collection"].map { it["id"] }).to eq([filter_one.id])
    end
  end

  context "with a product_category filter" do
    let(:variables) { {productCategoryIds: [product.product_category_id]} }

    it "returns only the filters of items belonging to those product_categories" do
      expect(execution["data"]["productFilters"]["collection"].map { it["id"] }).to eq([filter_one.id])
    end
  end

  context "with a without product_category filter" do
    let(:standalone_item) { create(:product, :standalone, organization:) }
    let!(:orphan_filter) { create(:product_filter, organization:, product: standalone_item) }
    let(:variables) { {withoutProductCategory: true} }

    it "returns only the filters of items not attached to any product_category" do
      expect(execution["data"]["productFilters"]["collection"].map { it["id"] }).to eq([orphan_filter.id])
    end
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "EU"} }

    it "returns matching filters" do
      expect(execution["data"]["productFilters"]["collection"].map { it["id"] }).to eq([filter_two.id])
    end
  end
end
