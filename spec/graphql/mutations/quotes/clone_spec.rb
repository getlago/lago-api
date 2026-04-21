# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Clone do
  let(:required_permission) { "quotes:clone" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, status: :draft) }

  let(:mutation) do
    <<~GQL
      mutation($input: CloneQuoteInput!) {
        cloneQuote(input: $input) {
          id
          number
          status
          version
          orderType
        }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:quote) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:clone"

  it "clones the given quote", :premium do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: quote.id}
      }
    )

    result_data = result["data"]["cloneQuote"]

    expect(result_data["id"]).to be_present
    expect(result_data["id"]).not_to eq(quote.id)
    expect(result_data["status"]).to eq("draft")
    expect(result_data["version"]).to eq(2)
    expect(result_data["number"]).to eq(quote.number)
    expect(result_data["orderType"]).to eq(quote.order_type)
  end

  context "when the quote belongs to another organization", :premium do
    let(:other_organization) { create(:organization, feature_flags: ["quote"]) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:foreign_quote) { create(:quote, organization: other_organization, customer: other_customer, status: :draft) }

    it "returns a GraphQL error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: foreign_quote.id}
        }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["extensions"]["code"]).to eq("not_found")
      expect(result["errors"].first["extensions"]["details"]["quote"]).to eq(["not_found"])
    end
  end
end
