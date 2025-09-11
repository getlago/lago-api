# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::PaymentsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  describe "GET /api/v1/customers/:external_id/payments" do
    subject { get_with_token(organization, "/api/v1/customers/#{customer.external_id}/payments", params) }

    let(:params) { {} }

    include_examples "requires API permission", "payment", "read"

    context "with invalid customer id" do
      subject { get_with_token(organization, "/api/v1/customers/foo/payments", {}) }

      it "returns a 404" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end

    it "returns customer's payments", :aggregate_failures do
      invoice = create(:invoice, organization:, customer:)
      invoice2 = create(:invoice, organization:, customer:)
      payment_request = create(:payment_request, organization:, customer:)
      first_payment = create(:payment, payable: invoice, customer:)
      second_payment = create(:payment, payable: invoice2, customer:)
      third_payment = create(:payment, payable: payment_request, customer:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:payments].count).to eq(3)
      expect(json[:payments].map { |r| r[:lago_id] }).to contain_exactly(
        first_payment.id,
        second_payment.id,
        third_payment.id
      )
    end

    context "with an invoice belonging to a different customer", :aggregate_failures do
      let(:params) { {invoice_id: invoice.id} }
      let(:invoice) { create(:invoice, organization:) }

      before do
        create(:payment, payable: invoice)
      end

      it "returns an empty result" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payments]).to be_empty
      end
    end

    context "with invoice" do
      let(:invoice) { create(:invoice, organization:, customer:) }
      let(:params) { {invoice_id: invoice.id} }
      let(:first_payment) { create(:payment, payable: invoice, customer:) }

      before do
        first_payment
        create(:payment)
      end

      it "returns invoice's payments", :aggregate_failures do
        subject
        expect(response).to have_http_status(:success)
        expect(json[:payments].map { |r| r[:lago_id] }).to contain_exactly(first_payment.id)
        expect(json[:payments].first[:invoice_ids].first).to eq(invoice.id)
      end
    end
  end
end
