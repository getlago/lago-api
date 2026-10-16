# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::InvoicesController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
  let(:legacy_invoice) { create(:invoice, organization:, customer:) }

  describe "GET /api/v2/invoices" do
    subject { get_with_token(organization, "/api/v2/invoices", params) }

    let(:params) { {} }

    before do
      contract_invoice
      legacy_invoice
    end

    include_examples "requires API permission", "invoice", "read"

    it "lists the catalog invoices only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoices].sole).to include(lago_id: contract_invoice.id, invoice_type: "contract", external_customer_id: customer.external_id)
      expect(json[:invoices].sole).not_to have_key(:fees)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :invoices, model: Invoice do
      let(:paginated_path) { "/api/v2/invoices" }
      let(:create_paginated_record) { ->(created_at) { create(:invoice, organization:, customer:, invoice_type: :contract, created_at:) } }
    end

    [{per_page: 1_000_000_000}, {page: 0}].each do |offset_params|
      context "with #{offset_params.keys.sole}, which the cursor replaces" do
        let(:params) { offset_params }

        it "returns a pagination error instead of the v1 page checks" do
          subject

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("invalid_pagination_parameter")
          expect(json[:error_details]).to eq(offset_params.keys.sole => {reason: "replaced_by_cursor"})
        end
      end
    end

    context "with filters" do
      let(:params) { {invoice_type: "advance_fees", billing_entity_codes: [billing_entity.code], statuses: ["finalized"]} }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:advance_fees_invoice) { create(:invoice, organization:, customer:, billing_entity:, invoice_type: :advance_charges) }

      before do
        advance_fees_invoice
        create(:invoice, organization:, customer:, invoice_type: :advance_charges)
      end

      it "passes them to the query" do
        subject

        expect(json[:invoices].map { it[:lago_id] }).to eq([advance_fees_invoice.id])
        expect(json[:invoices].sole[:invoice_type]).to eq("advance_fees")
      end
    end

    context "with an invoice type v2 does not serve" do
      let(:params) { {invoice_type: "subscription"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :invoice_type)).to eq(["value_is_invalid"])
      end
    end

    context "with an unknown billing entity code" do
      let(:params) { {billing_entity_codes: [organization.default_billing_entity.code, "unknown"]} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("billing_entity")
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

  describe "GET /api/v2/invoices/:id" do
    subject { get_with_token(organization, "/api/v2/invoices/#{invoice_id}") }

    let(:invoice_id) { contract_invoice.id }

    include_examples "requires API permission", "invoice", "read"

    it "returns the invoice with its details" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(lago_id: contract_invoice.id, invoice_type: "contract", contracts: [], fees: [])
      expect(json[:invoice]).not_to have_key(:customer)
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end

    context "when the invoice belongs to another organization" do
      let(:invoice_id) { create(:invoice, invoice_type: :contract).id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end
  end

  describe "POST /api/v2/invoices/:id/void" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/void", params) }

    let(:invoice) { create(:invoice, status:, payment_status: :pending, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }
    let(:params) { {} }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:))
    end
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }

    before do
      create(:fee, invoice:, subscription: nil, fee_type: :product,
        invoiceable: contract_rate_card.rate_card.product, contract: contract_rate_card.contract, contract_rate_card:, rate_card_rate:)
    end

    include_examples "requires API permission", "invoice", "write"

    it "voids the contract invoice and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(invoice.reload).to be_voided
      expect(json[:invoice]).to include(lago_id: invoice.id, status: "voided")
      expect(json[:invoice][:fees].pluck(:lago_id)).to eq(invoice.fees.ids)
    end

    context "when the invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end

    context "when the invoice is a draft" do
      let(:status) { :draft }

      it "returns a not voidable error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("not_voidable")
        expect(invoice.reload).to be_draft
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
        expect(invoice.reload).to be_finalized
      end
    end
  end
end
