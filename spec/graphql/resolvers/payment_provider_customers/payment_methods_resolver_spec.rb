# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentProviderCustomers::PaymentMethodsResolver do
  let(:required_permissions) { %w[customers:view payment_methods:view] }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, payment_provider: "stripe") }
  let(:connection) { create(:stripe_customer, customer:, organization:) }
  let(:other_connection) { create(:gocardless_customer, customer:, organization:) }

  let(:payment_method) { create(:payment_method, customer:, organization:, payment_provider_customer: connection) }
  let(:other_payment_method) do
    create(:payment_method, customer:, organization:, payment_provider_customer: other_connection, is_default: false)
  end

  let(:query) do
    <<~GQL
      query($id: ID!, $withDeleted: Boolean) {
        customer(id: $id) {
          id
          providerCustomer {
            id
            paymentMethods(limit: 5, withDeleted: $withDeleted) {
              collection { id }
              metadata { currentPage totalCount }
            }
          }
        }
      }
    GQL
  end

  before do
    connection
    other_connection
    payment_method
    other_payment_method
  end

  it "returns only the payment methods of the selected connection" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permissions,
      query:,
      variables: {id: customer.id}
    )

    payment_methods = result["data"]["customer"]["providerCustomer"]["paymentMethods"]

    expect(payment_methods["collection"].map { |pm| pm["id"] }).to contain_exactly(payment_method.id)
    expect(payment_methods["metadata"]["totalCount"]).to eq(1)
  end

  context "when withDeleted is true" do
    let(:deleted_payment_method) do
      create(:payment_method, customer:, organization:, payment_provider_customer: connection, deleted_at: Time.current)
    end

    before { deleted_payment_method }

    it "includes the discarded payment methods of the connection" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permissions,
        query:,
        variables: {id: customer.id, withDeleted: true}
      )

      payment_methods = result["data"]["customer"]["providerCustomer"]["paymentMethods"]

      expect(payment_methods["collection"].map { |pm| pm["id"] })
        .to contain_exactly(payment_method.id, deleted_payment_method.id)
    end
  end
end
