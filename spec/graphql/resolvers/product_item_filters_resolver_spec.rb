# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductItemFiltersResolver do
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
      query($searchTerm: String, $productItemId: ID) {
        productItemFilters(limit: 5, searchTerm: $searchTerm, productItemId: $productItemId) {
          collection { id name code }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product_item) { create(:product_item, organization:) }
  let!(:filter_one) { create(:product_item_filter, organization:, product_item:, name: "US cards") }
  let!(:filter_two) { create(:product_item_filter, organization:, name: "EU cards") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:view"

  it "returns the filters of the organization" do
    response = execution["data"]["productItemFilters"]

    expect(response["collection"].map { it["id"] }).to match_array([filter_one.id, filter_two.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with a product item filter" do
    let(:variables) { {productItemId: product_item.id} }

    it "returns only the filters of that item" do
      expect(execution["data"]["productItemFilters"]["collection"].map { it["id"] }).to eq([filter_one.id])
    end
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "EU"} }

    it "returns matching filters" do
      expect(execution["data"]["productItemFilters"]["collection"].map { it["id"] }).to eq([filter_two.id])
    end
  end
end
