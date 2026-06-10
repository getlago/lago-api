# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Products::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "products:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product) { create(:product, organization:, name: "Before") }

  let(:input) { {id: product.id, name: "After"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateProductInput!) {
        updateProduct(input: $input) {
          id name code
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:update"

  it "updates the product" do
    result_data = execution["data"]["updateProduct"]

    expect(result_data["id"]).to eq(product.id)
    expect(result_data["name"]).to eq("After")
  end

  context "when the product belongs to another organization" do
    let(:product) { create(:product) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
