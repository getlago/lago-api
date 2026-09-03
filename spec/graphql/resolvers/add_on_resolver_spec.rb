# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::AddOnResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "addons:view" }
  let(:organization) { membership.organization }
  let(:applied_add_on_list) { create_list(:applied_add_on, 3, add_on:, customer:) }
  let(:applied_add_on) { create(:applied_add_on, add_on:, customer: customer2) }
  let(:query) do
    <<~GQL
      query($addOnId: ID!) {
        addOn(id: $addOnId) {
          id name customersCount appliedAddOnsCount
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:add_on) { create_default(:add_on, organization:) }
  let_it_be(:customer) { create_default(:customer, organization:) }
  let_it_be(:customer2) { create_default(:customer, organization:) }

  before do
    customer
    customer2
    applied_add_on_list
    applied_add_on

    3.times do
      create(:subscription, customer:)
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "addons:view"

  it "returns a single add-on" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {addOnId: add_on.id}
    )

    add_on_response = result["data"]["addOn"]

    expect(add_on_response["id"]).to eq(add_on.id)
    expect(add_on_response["name"]).to eq(add_on.name)
    expect(add_on_response["customersCount"]).to eq(2)
    expect(add_on_response["appliedAddOnsCount"]).to eq(4)
  end

  context "when add-on is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {addOnId: "invalid"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
