# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PaymentRequestsController, type: :request do
  let(:organization) { create(:organization) }

  describe "POST /api/v1/payment_requests" do
    subject do
      post_with_token(
        organization,
        "/api/v1/payment_requests",
        {payment_request: params}
      )
    end

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

      subject

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

  describe "GET /api/v1/payment_requests" do
    subject { get_with_token(organization, "/api/v1/payment_requests", params) }

    let(:params) { {} }

    it "returns organization's payment requests", :aggregate_failures do
      first_customer = create(:customer, organization:)
      second_customer = create(:customer, organization:)
      first_payment_request = create(:payment_request, customer: first_customer)
      second_payment_request = create(:payment_request, customer: second_customer)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(2)
      expect(json[:payment_requests].map { |r| r[:lago_id] }).to contain_exactly(
        first_payment_request.id,
        second_payment_request.id
      )
    end

    context "with a not found customer", :aggregate_failures do
      let(:params) { {external_customer_id: SecureRandom.uuid} }

      before do
        customer = create(:customer, organization:)
        create(:payment_request, customer:)
      end

      it "returns an empty result" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payment_requests]).to be_empty
      end
    end

    context "with customer" do
      let(:params) { {external_customer_id: customer.external_id} }
      let(:customer) { create(:customer, organization:) }

      it "returns customer's payment requests", :aggregate_failures do
        first_payment_request = create(:payment_request, customer:)
        invoice = create(:invoice, customer:)
        create(:payment_request_applied_invoice, invoice:, payment_request: first_payment_request)
        create(:payment_request)

        subject

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
