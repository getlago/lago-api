# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Create do
  let(:required_permission) { "quotes:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateQuoteInput!) {
        createQuote(input: $input) {
          id
          number
          status
          orderType
          customer { id }
          organization { id }
        }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:quote) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:create"

  it "creates a quote", :premium do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          orderType: "one_off"
        }
      }
    )

    result_data = result["data"]["createQuote"]

    expect(result_data["id"]).to be_present
    expect(result_data["number"]).to match(/\AQT-\d{4}-\d{4}\z/)
    expect(result_data["status"]).to eq("draft")
    expect(result_data["orderType"]).to eq("one_off")
    expect(result_data["customer"]["id"]).to eq(customer.id)
    expect(result_data["organization"]["id"]).to eq(organization.id)
  end

  context "when an owner belongs to a different organization", :premium do
    let(:other_organization) { create(:organization) }
    let(:foreign_membership) { create(:membership, organization: other_organization) }

    it "returns a GraphQL error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            orderType: "one_off",
            owners: [foreign_membership.user_id]
          }
        }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["extensions"]["code"]).to eq("unprocessable_entity")
      expect(result["errors"].first["extensions"]["details"]["owners"]).to eq(["not_found"])
    end
  end
end
