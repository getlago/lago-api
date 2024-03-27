# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Taxes::Create, type: :graphql do
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

  it "creates a tax" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
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

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {input:}
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {input:}
      )

      expect_forbidden_error(result)
    end
  end
end
