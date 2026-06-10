# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Products::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "products:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:input) do
    {
      name: "Cards",
      code: "cards",
      description: "Card products",
      invoiceDisplayName: "Cards"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateProductInput!) {
        createProduct(input: $input) {
          id name code description invoiceDisplayName
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:create"

  it "creates a product" do
    result_data = execution["data"]["createProduct"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("Cards")
    expect(result_data["code"]).to eq("cards")
    expect(result_data["description"]).to eq("Card products")
    expect(result_data["invoiceDisplayName"]).to eq("Cards")
  end
end
