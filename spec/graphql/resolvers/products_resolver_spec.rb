# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductsResolver do
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "products:view" }
  let(:organization) { membership.organization }
  let(:variables) { {} }
  let(:query) do
    <<~GQL
      query($searchTerm: String, $productType: ProductTypeEnum, $productCategoryIds: [ID!], $withoutProductCategory: Boolean) {
        products(limit: 5, searchTerm: $searchTerm, productType: $productType, productCategoryIds: $productCategoryIds, withoutProductCategory: $withoutProductCategory) {
          collection { id name code productType }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end
  let(:product_category) { create(:product_category, organization:) }
  let!(:usage_item) { create(:product, organization:, product_category:, name: "Storage", code: "storage") }
  let!(:fixed_item) { create(:product, :fixed, :standalone, organization:, name: "Seats", code: "seats") }

  let_it_be(:membership) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:view"

  it "returns the products of the organization" do
    response = execution["data"]["products"]

    expect(response["collection"].map { it["id"] }).to match_array([usage_item.id, fixed_item.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with an item type filter" do
    let(:variables) { {productType: "fixed"} }

    it "returns only matching items" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to eq([fixed_item.id])
    end
  end

  context "with a product_category filter" do
    let(:variables) { {productCategoryIds: [product_category.id]} }

    it "returns only the items of those product_categories" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to eq([usage_item.id])
    end
  end

  context "with a without product_category filter" do
    let(:variables) { {withoutProductCategory: true} }

    it "returns only the items not attached to any product_category" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to eq([fixed_item.id])
    end
  end

  context "with product_category and without product_category filters combined" do
    let(:variables) { {productCategoryIds: [product_category.id], withoutProductCategory: true} }

    it "returns the union of both" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to match_array([usage_item.id, fixed_item.id])
    end
  end
end
