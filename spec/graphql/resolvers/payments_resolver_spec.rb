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

    it "returns a list of payments" do
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

    it "returns a list of payments" do
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

  context "when currency is present" do
    let(:query) do
      <<~GQL
        query($currency: CurrencyEnum!) {
          payments(currency: $currency, limit: 5) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    let(:usd_invoice) { create(:invoice, customer:, organization:, currency: "USD") }
    let!(:usd_payment) { create(:payment, payable: usd_invoice, amount_currency: "USD") }

    it "returns only payments matching the currency" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {currency: "USD"}
      )

      ids = result["data"]["payments"]["collection"].map { |p| p["id"] }
      expect(ids).to contain_exactly(usd_payment.id)
    end
  end

  context "with list filters" do
    subject(:response) do
      execute_graphql(current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:, variables:)
    end

    let(:query) do
      <<~GQL
        query($paymentStatus: [PayablePaymentStatusEnum!], $amountFrom: BigInt, $amountTo: BigInt,
          $receiptNumber: String, $createdAtFrom: ISO8601Date, $createdAtTo: ISO8601Date,
          $paymentProviderType: [ProviderTypeEnum!], $paymentMethodType: [PaymentProviderMethodTypeEnum!],
          $invoiceNumber: String, $paymentType: [PaymentTypeEnum!], $payableType: [PayableTypeEnum!],
          $searchTerm: String, $currency: CurrencyEnum, $invoiceId: ID, $page: Int) {
          payments(paymentStatus: $paymentStatus, amountFrom: $amountFrom, amountTo: $amountTo,
            receiptNumber: $receiptNumber, createdAtFrom: $createdAtFrom, createdAtTo: $createdAtTo,
            paymentProviderType: $paymentProviderType, paymentMethodType: $paymentMethodType,
            invoiceNumber: $invoiceNumber, paymentType: $paymentType, payableType: $payableType,
            searchTerm: $searchTerm, currency: $currency, invoiceId: $invoiceId, page: $page, limit: 1) {
            collection { id amountCents }
            metadata { totalCount currentPage }
          }
        }
      GQL
    end

    before do
      invoice1.update!(number: "FILTER-INVOICE", total_amount_cents: 9_007_199_254_740_993)
      Payment.find_by!(payable: invoice2).update!(created_at: Time.utc(2026, 9, 8, 12))
      organization.default_billing_entity.update!(timezone: "America/Los_Angeles")
      payment.update!(amount_cents: 9_007_199_254_740_993, amount_currency: "USD",
        payable_payment_status: "processing", payment_type: "manual", reference: "Filter transfer",
        payment_provider: create(:gocardless_provider, organization:),
        provider_payment_method_data: {type: "sepa_debit"}, created_at: Time.utc(2026, 9, 4, 12))
      create(:payment_receipt, organization:, payment:, number: "FILTER-RECEIPT")
    end

    [
      {paymentStatus: ["processing"]},
      {amountFrom: "9007199254740993"},
      {amountFrom: "9007199254740993", amountTo: "9007199254740993"},
      {receiptNumber: "filter-receipt"},
      {createdAtFrom: "2026-09-01", createdAtTo: "2026-09-07"},
      {createdAtTo: "2026-09-04"},
      {paymentProviderType: ["gocardless"]},
      {paymentMethodType: ["sepa_debit"]},
      {invoiceNumber: "filter-invoice"},
      {paymentType: ["manual"]},
      {searchTerm: "Filter transfer"},
      {currency: "USD"},
      {paymentStatus: ["processing"], amountFrom: "100", currency: "USD"}
    ].each do |filter_variables|
      context "with #{filter_variables.keys.join(", ")}" do
        let(:variables) { filter_variables }

        it "applies the filter and returns the correct count" do
          expect(response["errors"]).to be_nil
          expect(response.dig("data", "payments", "collection").map { |item| item["id"] }).to eq([payment.id])
          expect(response.dig("data", "payments", "metadata", "totalCount")).to eq(1)
        end
      end
    end

    context "with payable type" do
      let(:variables) { {payableType: ["PaymentRequest"], invoiceNumber: invoice1.number.downcase} }
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice1, invoice2]) }

      before { payment.update!(payable: payment_request) }

      it "matches invoices on a payment request once" do
        expect(response["errors"]).to be_nil
        expect(response.dig("data", "payments", "collection").map { |item| item["id"] }).to eq([payment.id])
        expect(response.dig("data", "payments", "metadata", "totalCount")).to eq(1)
      end
    end

    [
      {paymentStatus: ["unknown"]}, {paymentProviderType: ["unknown"]},
      {paymentMethodType: ["unknown"]}, {paymentType: ["unknown"]}, {payableType: ["unknown"]},
      {amountFrom: "-1"}, {amountTo: "-1"}, {amountFrom: "500", amountTo: "100"},
      {amountFrom: "9223372036854775808"}, {receiptNumber: "x" * 256},
      {invoiceNumber: "x" * 256}, {invoiceId: "invalid"}, {createdAtFrom: "2026-02-30"}
    ].each do |invalid_variables|
      context "with invalid #{invalid_variables.keys.join(", ")}" do
        let(:variables) { invalid_variables }

        it "returns a GraphQL error" do
          expect(response["errors"]).to be_present
          expect(response["data"]).to be_nil
        end
      end
    end
  end
end
