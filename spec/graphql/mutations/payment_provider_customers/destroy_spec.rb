# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviderCustomers::Destroy do
  let(:required_permissions) { "customers:update" }
  let(:membership) { create(:membership, organization:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:payment_provider_customer) { create(:stripe_customer, organization:, customer:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyPaymentProviderCustomerInput!) {
        destroyPaymentProviderCustomer(input: $input) {
          id
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  it "deletes a payment provider customer" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permissions,
      query: mutation,
      variables: {
        input: {id: payment_provider_customer.id}
      }
    )

    data = result["data"]["destroyPaymentProviderCustomer"]
    expect(data["id"]).to eq(payment_provider_customer.id)
  end

  context "when payment provider customer is not found" do
    let(:payment_provider_customer) { create(:stripe_customer) }

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permissions,
        query: mutation,
        variables: {
          input: {id: payment_provider_customer.id}
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
