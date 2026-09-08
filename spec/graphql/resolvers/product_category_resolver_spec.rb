# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductCategoryResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {productCategoryId: product_category.id}
    )
  end

  let(:required_permission) { "product_categories:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_category) { create(:product_category, organization:) }

  let(:query) do
    <<~GQL
      query($productCategoryId: ID!) {
        productCategory(id: $productCategoryId) {
          id name code
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_categories:view"

  it "returns a single product_category" do
    response = execution["data"]["productCategory"]

    expect(response["id"]).to eq(product_category.id)
    expect(response["name"]).to eq(product_category.name)
  end

  context "when the product_category belongs to another organization" do
    let(:product_category) { create(:product_category) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
