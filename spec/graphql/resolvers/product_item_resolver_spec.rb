# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductItemResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {productItemId: product_item.id}
    )
  end

  let(:required_permission) { "product_items:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_item) { create(:product_item, organization:) }

  let(:query) do
    <<~GQL
      query($productItemId: ID!) {
        productItem(id: $productItemId) {
          id name code itemType
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:view"

  it "returns a single product item" do
    response = execution["data"]["productItem"]

    expect(response["id"]).to eq(product_item.id)
    expect(response["name"]).to eq(product_item.name)
    expect(response["itemType"]).to eq("usage")
  end

  context "when the product item belongs to another organization" do
    let(:product_item) { create(:product_item) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
