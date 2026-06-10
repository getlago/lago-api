# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductCategories::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "product_categories:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_category) { create(:product_category, organization:, name: "Before") }

  let(:input) { {id: product_category.id, name: "After"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateProductCategoryInput!) {
        updateProductCategory(input: $input) {
          id name code
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_categories:update"

  it "updates the product_category" do
    result_data = execution["data"]["updateProductCategory"]

    expect(result_data["id"]).to eq(product_category.id)
    expect(result_data["name"]).to eq("After")
  end

  context "when the product_category belongs to another organization" do
    let(:product_category) { create(:product_category) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
