# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviderCustomers::Create do
  let(:required_permission) { "customers:update" }
  let(:membership) { create(:membership, organization:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_eu") }

  let(:mutation) do
    <<-GQL
      mutation($input: CreatePaymentProviderCustomerInput!) {
        createPaymentProviderCustomer(input: $input) {
          id
          code
          isDefault
          providerCustomerId
          providerPaymentMethods
          syncWithProvider
        }
      }
    GQL
  end

  before { stripe_provider }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  it "creates a payment provider customer connection" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          paymentProvider: "stripe",
          paymentProviderCode: "stripe_eu",
          code: "stripe_eu_connection",
          providerCustomerId: "cus_123",
          providerPaymentMethods: %w[card sepa_debit]
        }
      }
    )

    data = result["data"]["createPaymentProviderCustomer"]
    expect(data["id"]).to be_present
    expect(data["code"]).to eq("stripe_eu_connection")
    expect(data["isDefault"]).to be(true)
    expect(data["providerCustomerId"]).to eq("cus_123")
    expect(data["providerPaymentMethods"]).to match_array(%w[card sepa_debit])
  end

  context "when the customer already has a default connection" do
    before { create(:adyen_customer, organization:, customer:, is_default: true) }

    it "does not mark the new connection as default" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            paymentProvider: "stripe",
            code: "stripe_eu_connection",
            providerCustomerId: "cus_123"
          }
        }
      )

      data = result["data"]["createPaymentProviderCustomer"]
      expect(data["isDefault"]).to be(false)
    end
  end

  context "when neither providerCustomerId nor syncWithProvider is given" do
    it "returns null without an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {customerId: customer.id, paymentProvider: "stripe", code: "stripe_eu_connection"}
        }
      )

      expect(result["errors"]).to be_nil
      expect(result["data"]["createPaymentProviderCustomer"]).to be_nil
    end
  end

  context "when the customer is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {customerId: "unknown", paymentProvider: "stripe", providerCustomerId: "cus_123"}
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
