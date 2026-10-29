# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::InvoicesController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }

  describe "GET /api/v2/customers/:external_customer_id/invoices" do
    subject { get_with_token(organization, "/api/v2/customers/#{external_customer_id}/invoices", params) }

    let(:external_customer_id) { customer.external_id }
    let(:params) { {} }

    before do
      contract_invoice
      create(:invoice, organization:, customer:)
      create(:invoice, organization:, customer: create(:customer, organization:), invoice_type: :contract)
    end

    include_examples "requires API permission", "invoice", "read"

    it "lists the catalog invoices of the customer only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoices].sole).to include(lago_id: contract_invoice.id, invoice_type: "contract", external_customer_id: customer.external_id)
      expect(json[:invoices].sole).not_to have_key(:fees)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :invoices, model: Invoice, sort: Api::V2::InvoiceIndex::SORT do
      let(:paginated_path) { "/api/v2/customers/#{customer.external_id}/invoices" }
      let(:create_paginated_record) { ->(created_at) { create(:invoice, organization:, customer:, invoice_type: :contract, created_at:) } }
    end

    context "with filters" do
      let(:params) { {invoice_type: "advance_fees"} }
      let(:advance_fees_invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:)) }

      before do
        create(:fee, invoice: advance_fees_invoice, subscription: nil, fee_type: :product,
          invoiceable: contract_rate_card.rate_card.product, contract: contract_rate_card.contract, contract_rate_card:,
          rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card))
      end

      it "passes them to the query" do
        subject

        expect(json[:invoices].map { it[:lago_id] }).to eq([advance_fees_invoice.id])
        expect(json[:invoices].sole[:invoice_type]).to eq("advance_fees")
      end
    end

    context "with an invoice type v2 does not serve" do
      let(:params) { {invoice_type: "credit"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "invoice_type", meta: {}}])
      end
    end

    context "when the customer does not exist" do
      let(:external_customer_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "with expands" do
      let(:params) { {expands: %w[fees], limit: 0} }

      it "rejects them before validating pagination, as a list never expands" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:details]).to eq([{code: "not_expandable", field: "expands", meta: {invalid_values: ["fees"]}}])
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
