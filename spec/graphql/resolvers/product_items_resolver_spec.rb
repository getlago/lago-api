# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductItemsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "product_items:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }

  let(:query) do
    <<~GQL
      query($searchTerm: String, $itemTypes: [ProductItemTypeEnum!], $productId: ID) {
        productItems(limit: 5, searchTerm: $searchTerm, itemTypes: $itemTypes, productId: $productId) {
          collection { id name code itemType }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product) { create(:product, organization:) }
  let!(:usage_item) { create(:product_item, organization:, product:, name: "Storage", code: "storage") }
  let!(:fixed_item) { create(:product_item, :fixed, :standalone, organization:, name: "Seats", code: "seats") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:view"

  it "returns the product items of the organization" do
    response = execution["data"]["productItems"]

    expect(response["collection"].map { it["id"] }).to match_array([usage_item.id, fixed_item.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with an item type filter" do
    let(:variables) { {itemTypes: %w[fixed]} }

    it "returns only matching items" do
      expect(execution["data"]["productItems"]["collection"].map { it["id"] }).to eq([fixed_item.id])
    end
  end

  context "with a product filter" do
    let(:variables) { {productId: product.id} }

    it "returns only the items of that product" do
      expect(execution["data"]["productItems"]["collection"].map { it["id"] }).to eq([usage_item.id])
    end
  end
end
