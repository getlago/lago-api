# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Customers::Destroy do
  let(:required_permission) { "customers:delete" }
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
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:delete"

  it "deletes a customer" do
    result = execute_query(
      query: mutation,
      input: {id: customer.id}
    )

    data = result["data"]["destroyCustomer"]
    expect(data["id"]).to eq(customer.id)
  end

  context "when the organization is the shadow of a migration" do
    before { create(:billing_engine_migration, organization: create(:organization), shadow_organization: organization) }

    it "deletes the customer" do
      result = execute_query(
        query: mutation,
        input: {id: customer.id}
      )

      expect(result["errors"]).to be_nil
      expect(result["data"]["destroyCustomer"]["id"]).to eq(customer.id)
      expect(customer.reload).to be_discarded
    end
  end
end
