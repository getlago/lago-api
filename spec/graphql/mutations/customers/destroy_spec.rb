# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Customers::Destroy do
  let(:required_permissions) { "customers:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyCustomerInput!) {
        destroyCustomer(input: $input) {
          id
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "customers:delete"

  it "deletes a customer" do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permissions,
      query: mutation,
      variables: {
        input: {id: customer.id}
      }
    )

    data = result["data"]["destroyCustomer"]
    expect(data["id"]).to eq(customer.id)
  end
end
