# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentsResolver do
  let(:required_permission) { "payments:view" }
  let(:query) {}

  let!(:payment) { create(:payment, payable: invoice1) }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice1) { create(:invoice, customer:, organization:) }
  let(:invoice2) { create(:invoice, customer:, organization:) }

  before do
    create(:payment, payable: invoice2)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "payments:view"

  context "when invoice id is present" do
    let(:query) do
      <<~GQL
        query($invoiceId: ID!) {
          payments(invoiceId: $invoiceId, limit: 5) {
            collection {
              id
              amountCents
              customer { id }
              paymentProviderType
              payable {
                ... on Invoice { id payableType }
                ... on PaymentRequest { id payableType }
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of payments", :aggregate_failures do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          invoiceId: invoice1.id
        }
      )

      payments_response = result["data"]["payments"]

      expect(payments_response["collection"].count).to eq(1)
      expect(payments_response["collection"].first["id"]).to eq(payment.id)
      expect(payments_response["collection"].first["amountCents"]).to eq(payment.amount_cents.to_s)
      expect(payments_response["collection"].first["paymentProviderType"]).to eq("stripe")
      expect(payments_response["collection"].first["payable"]["id"]).to eq(invoice1.id)
      expect(payments_response["collection"].first["payable"]["payableType"]).to eq("Invoice")
      expect(payments_response["collection"].first["customer"]["id"]).to eq(customer.id)
    end
  end

  context "when external customer id is present" do
    let(:query) do
      <<~GQL
        query($externalCustomerId: ID!) {
          payments(externalCustomerId: $externalCustomerId, limit: 5) {
            collection {
              id
              amountCents
              customer { id }
              paymentProviderType
              payable {
                ... on Invoice { id }
                ... on PaymentRequest { id }
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of payments", :aggregate_failures do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          externalCustomerId: customer.external_id
        }
      )

      payments_response = result["data"]["payments"]

      expect(payments_response["collection"].count).to eq(2)
      expect(payments_response["collection"].map { |payable| payable.dig("payable", "id") })
        .to contain_exactly(invoice1.id, invoice2.id)
    end
  end
end
