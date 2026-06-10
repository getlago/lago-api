# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductItems::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "product_items:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_item) { create(:product_item, organization:, name: "Before") }

  let(:input) { {id: product_item.id, name: "After"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateProductItemInput!) {
        updateProductItem(input: $input) {
          id name code
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:update"

  it "updates the product item" do
    result_data = execution["data"]["updateProductItem"]

    expect(result_data["id"]).to eq(product_item.id)
    expect(result_data["name"]).to eq("After")
  end

  context "when the product item belongs to another organization" do
    let(:product_item) { create(:product_item) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
