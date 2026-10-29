# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::PaymentsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:payment) { create(:payment, payable: invoice) }
  let(:customer_path) { "/api/v2/customers/#{customer.external_id}" }

  describe "GET /api/v2/customers/:external_id/payments" do
    subject { get_with_token(organization, "#{customer_path}/payments", params) }

    let(:params) { {} }

    before do
      payment
      create(:payment, payable: create(:invoice, organization:))
    end

    include_examples "requires API permission", "payment", "read"

    it "lists the payments of the customer only, with the v2 payload" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payments].sole).to include(
        lago_id: payment.id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        lago_payable_id: invoice.id,
        payable_type: "Invoice",
        lago_invoice_ids: [invoice.id],
        currency: "EUR",
        payment_provider_type: "stripe"
      )
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "with a deleted customer sharing the external id" do
      let(:customer) { create(:customer, organization:, external_id: "reused") }

      before do
        deleted_customer = create(:customer, organization:, external_id: "reused", deleted_at: Time.current)
        create(:payment, payable: create(:invoice, organization:, customer: deleted_customer))
      end

      it "lists the payments of the current customer only" do
        subject

        expect(json[:payments].map { it[:lago_id] }).to eq([payment.id])
      end
    end

    context "with a payment on a payment request" do
      let(:other_invoice) { create(:invoice, organization:, customer:) }
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice, other_invoice]) }
      let(:payment) { create(:payment, payable: payment_request) }

      it "lists the invoices the request covers" do
        subject

        expect(json[:payments].sole).to include(payable_type: "PaymentRequest", lago_payable_id: payment_request.id)
        expect(json[:payments].sole[:lago_invoice_ids]).to match_array([invoice.id, other_invoice.id])
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :payments, model: Payment do
      let(:paginated_path) { "#{customer_path}/payments" }
      let(:create_paginated_record) do
        ->(created_at) { create(:payment, payable: create(:invoice, organization:, customer:), created_at:) }
      end
    end

    context "with offset pagination parameters" do
      let(:params) { {page: 2} }

      it "refuses them, as the list pages with cursors" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_pagination_parameter")
      end
    end

    context "with expands" do
      let(:params) { {expands: %w[customer]} }

      it "refuses them, as a list never expands" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with an unknown customer" do
      let(:customer_path) { "/api/v2/customers/unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
