# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviderCustomers::Update do
  let(:required_permission) { "customers:update" }
  let(:payment_provider_customer) do
    create(:stripe_customer, organization:, customer:, code: "old_code", provider_payment_methods: %w[card])
  end
  let(:mutation) do
    <<-GQL
      mutation($input: UpdatePaymentProviderCustomerInput!) {
        updatePaymentProviderCustomer(input: $input) {
          id
          code
          providerPaymentMethods
          syncWithProvider
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership, organization:) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before { payment_provider_customer }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  it "updates the code and the provider payment methods" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: payment_provider_customer.id, code: "new_code", providerPaymentMethods: %w[card sepa_debit]}
      }
    )

    data = result["data"]["updatePaymentProviderCustomer"]
    expect(data["id"]).to eq(payment_provider_customer.id)
    expect(data["code"]).to eq("new_code")
    expect(data["providerPaymentMethods"]).to match_array(%w[card sepa_debit])
  end

  context "when updating only the code of a non-stripe connection" do
    let(:payment_provider_customer) { create(:adyen_customer, organization:, customer:, code: "old_code") }

    it "updates the code" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: payment_provider_customer.id, code: "new_code"}
        }
      )

      data = result["data"]["updatePaymentProviderCustomer"]
      expect(data["code"]).to eq("new_code")
    end
  end

  context "when editing a non-stripe connection with provider payment methods" do
    let(:payment_provider_customer) { create(:adyen_customer, organization:, customer:, code: "old_code") }

    it "updates the code and ignores the provider payment methods" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: payment_provider_customer.id, code: "new_code", providerPaymentMethods: %w[card]}
        }
      )

      data = result["data"]["updatePaymentProviderCustomer"]
      expect(data["code"]).to eq("new_code")
    end
  end

  context "when updating sync_with_provider" do
    it "updates sync_with_provider" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: payment_provider_customer.id, syncWithProvider: true}
        }
      )

      data = result["data"]["updatePaymentProviderCustomer"]
      expect(data["syncWithProvider"]).to be(true)
    end
  end

  context "when the customer has no default payment provider" do
    let(:payment_provider_customer) do
      create(:stripe_customer, organization:, customer:, provider_customer_id: "cus_123", provider_payment_methods: %w[card])
    end

    before { allow(Stripe::Customer).to receive(:update) }

    it "saves the connection without pushing the customer to the provider" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: payment_provider_customer.id, providerCustomerId: "cus_123", providerPaymentMethods: %w[card sepa_debit]}
        }
      )

      expect(result["errors"]).to be_nil
      expect(customer.payment_provider).to be_nil
      expect(result["data"]["updatePaymentProviderCustomer"]["providerPaymentMethods"]).to match_array(%w[card sepa_debit])
      expect(payment_provider_customer.reload.provider_payment_methods).to eq(%w[card sepa_debit])
      expect(Stripe::Customer).not_to have_received(:update)
    end
  end

  context "when payment provider customer is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: "unknown", code: "new_code"}
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
