# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Taxes::Create do
  let(:membership) { create(:membership) }
  let(:input) do
    {
      name: "Tax name",
      code: "tax-code",
      description: "Tax description",
      rate: 15.0
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: TaxCreateInput!) {
        createTax(input: $input) {
          id name code description rate addOnsCount plansCount chargesCount customersCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:taxes:update"

  it "creates a tax" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: "organization:taxes:update",
      query: mutation,
      variables: {input:}
    )

    expect(result["data"]["createTax"]).to include(
      "id" => String,
      "name" => "Tax name",
      "code" => "tax-code",
      "description" => "Tax description",
      "rate" => 15.0
    )
  end

  it "returns a forbidden error without the organization:taxes:update permission" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [],
      query: mutation,
      variables: {input:}
    )

    expect(result["errors"].first["extensions"]["code"]).to eq("forbidden")
  end
end
