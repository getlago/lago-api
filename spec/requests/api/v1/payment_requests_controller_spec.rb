# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PaymentRequestsController, type: :request do
  let(:organization) { create(:organization) }

  describe "create" do
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:params) do
      {
        email: customer.email,
        external_customer_id: customer.external_id,
        lago_invoice_ids: [invoice.id]
      }
    end

    it "delegates to PaymentRequests::CreateService", :aggregate_failures do
      payment_request = create(:payment_request, invoices: [invoice], customer:)
      allow(PaymentRequests::CreateService).to receive(:call).and_return(
        BaseService::Result.new.tap { |r| r.payment_request = payment_request }
      )

      post_with_token(organization, "/api/v1/payment_requests", {payment_request: params})

      expect(PaymentRequests::CreateService).to have_received(:call).with(
        organization:,
        params: {
          email: customer.email,
          external_customer_id: customer.external_id,
          lago_invoice_ids: [invoice.id]
        }
      )

      expect(response).to have_http_status(:success)
      expect(json[:payment_request][:lago_id]).to eq(payment_request.id)
      expect(json[:payment_request][:invoices].map { |i| i[:lago_id] }).to contain_exactly(invoice.id)
      expect(json[:payment_request][:customer][:lago_id]).to eq(customer.id)
    end
  end

  describe "index" do
    it "returns organization's payment requests", :aggregate_failures do
      first_customer = create(:customer, organization:)
      second_customer = create(:customer, organization:)
      first_payment_request = create(:payment_request, customer: first_customer)
      second_payment_request = create(:payment_request, customer: second_customer)

      get_with_token(organization, "/api/v1/payment_requests")

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(2)
      expect(json[:payment_requests].map { |r| r[:lago_id] }).to contain_exactly(
        first_payment_request.id,
        second_payment_request.id
      )
    end

    context "with a not found customer", :aggregate_failures do
      it "returns an empty result" do
        get_with_token(
          organization,
          "/api/v1/payment_requests?external_customer_id=unknown"
        )

        expect(response).to have_http_status(:success)
        expect(json[:payment_requests]).to be_empty
      end
    end

    context "with customer" do
      let(:customer) { create(:customer, organization:) }

      it "returns customer's payment requests", :aggregate_failures do
        first_payment_request = create(:payment_request, customer:)
        invoice = create(:invoice, customer:)
        create(:payment_request_applied_invoice, invoice:, payment_request: first_payment_request)
        create(:payment_request)

        get_with_token(
          organization,
          "/api/v1/payment_requests?external_customer_id=#{customer.external_id}"
        )

        expect(response).to have_http_status(:success)
        expect(json[:payment_requests].map { |r| r[:lago_id] }).to contain_exactly(
          first_payment_request.id
        )
        expect(json[:payment_requests].first[:customer][:lago_id]).to eq(customer.id)
        expect(json[:payment_requests].first[:invoices].first[:lago_id]).to eq(invoice.id)
      end
    end
  end
end
