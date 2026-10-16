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

    it_behaves_like "a cursor paginated v2 endpoint", collection: :invoices, model: Invoice do
      let(:paginated_path) { "/api/v2/customers/#{customer.external_id}/invoices" }
      let(:create_paginated_record) { ->(created_at) { create(:invoice, organization:, customer:, invoice_type: :contract, created_at:) } }
    end

    context "with filters" do
      let(:params) { {invoice_type: "advance_fees"} }
      let(:advance_fees_invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }

      before { advance_fees_invoice }

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
        expect(json.dig(:error_details, :invoice_type)).to eq(["value_is_invalid"])
      end
    end

    context "when the customer does not exist" do
      let(:external_customer_id) { "unknown" }

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
