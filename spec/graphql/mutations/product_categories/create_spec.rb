# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductCategories::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "product_categories:create" }
  let(:organization) { membership.organization }
  let(:input) do
    {
      name: "Cards",
      code: "cards",
      description: "Card product_categories",
      invoiceDisplayName: "Cards"
    }
  end
  let(:mutation) do
    <<-GQL
      mutation($input: CreateProductCategoryInput!) {
        createProductCategory(input: $input) {
          id name code description invoiceDisplayName
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_categories:create"

  it "creates a product_category" do
    result_data = execution["data"]["createProductCategory"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("Cards")
    expect(result_data["code"]).to eq("cards")
    expect(result_data["description"]).to eq("Card product_categories")
    expect(result_data["invoiceDisplayName"]).to eq("Cards")
  end
end
