# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {productId: product.id}
    )
  end

  let(:required_permission) { "products:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product) { create(:product, organization:) }

  let(:query) do
    <<~GQL
      query($productId: ID!) {
        product(id: $productId) {
          id name code
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:view"

  it "returns a single product" do
    response = execution["data"]["product"]

    expect(response["id"]).to eq(product.id)
    expect(response["name"]).to eq(product.name)
  end

  context "when the product belongs to another organization" do
    let(:product) { create(:product) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
