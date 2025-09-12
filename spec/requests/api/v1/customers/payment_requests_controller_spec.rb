# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::PaymentRequestsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:external_id) { customer.external_id }

  describe "GET /api/v1/customers/:external_id/payment_requests" do
    subject { get_with_token(organization, "/api/v1/customers/#{external_id}/payment_requests", params) }

    let(:params) { {} }

    include_examples "requires API permission", "payment_request", "read"

    it "returns customer's payment requests" do
      first_payment_request = create(:payment_request, customer:)
      second_payment_request = create(:payment_request, customer:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(2)
      expect(json[:payment_requests].map { |r| r[:lago_id] }).to contain_exactly(
        first_payment_request.id,
        second_payment_request.id
      )
    end

    context "with unknown customer" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end

    context "with customer from another organization" do
      let(:customer) { create(:customer) }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end

    context "with payment_status" do
      let(:params) { {payment_status: ["failed"]} }

      it "returns customer's payment requests" do
        invoice = create(:invoice, customer:)
        first_payment_request = create(:payment_request, customer:, invoices: [invoice], payment_status: "failed")
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
