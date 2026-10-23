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

    it_behaves_like "a cursor paginated v2 endpoint", collection: :invoices, model: Invoice, sort: Api::V2::InvoiceIndex::SORT do
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
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:)) }
      let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }

      before do
        [advance_fees_invoice, create(:invoice, organization:, customer:, invoice_type: :advance_charges)].each do |invoice|
          create(:fee, invoice:, subscription: nil, fee_type: :product, invoiceable: contract_rate_card.rate_card.product,
            contract: contract_rate_card.contract, contract_rate_card:, rate_card_rate:)
        end
      end

      it "passes them to the query" do
        subject

        expect(json[:invoices].map { it[:lago_id] }).to eq([advance_fees_invoice.id])
        expect(json[:invoices].sole[:invoice_type]).to eq("advance_fees")
      end
    end

    %i[external_customer_id customer_external_id].each do |filter|
      context "with the #{filter} filter" do
        let(:params) { {filter => customer.external_id} }

        before { create(:invoice, organization:, customer: create(:customer, organization:), invoice_type: :contract) }

        it "lists the catalog invoices of that customer only" do
          subject

          expect(json[:invoices].map { it[:lago_id] }).to eq([contract_invoice.id])
        end
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

    it "returns the flat invoice" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(lago_id: contract_invoice.id, invoice_type: "contract")
      expect(json[:invoice]).not_to include(:fees, :applied_taxes, :customer, :contracts)
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

  describe "expansions" do
    subject { get_with_token(organization, "/api/v2/invoices/#{invoice_id}", {expands: names}) }

    let(:invoice_id) { contract_invoice.id }
    let(:names) { %w[fees applied_taxes customer contracts applied_invoice_custom_sections error_details] }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:)) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
    let(:fee_attributes) do
      {
        invoice: contract_invoice,
        subscription: nil,
        fee_type: :product,
        invoiceable: contract_rate_card.rate_card.product,
        contract: contract_rate_card.contract,
        contract_rate_card:,
        rate_card_rate:
      }
    end
    let(:fee) { create(:fee, fee_attributes) }
    let(:applied_tax) { create(:invoice_applied_tax, invoice: contract_invoice) }

    before do
      fee
      applied_tax
    end

    it "embeds each requested record after the invoice" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:invoice].keys.last(6)).to eq(names.map(&:to_sym))
      expect(json[:invoice][:fees].map { it[:lago_id] }).to eq([fee.id])
      expect(json[:invoice][:fees].sole).not_to have_key(:applied_taxes)
      expect(json[:invoice][:applied_taxes].map { it[:lago_id] }).to eq([applied_tax.id])
      expect(json[:invoice][:customer]).to include(lago_id: customer.id, external_id: customer.external_id)
      expect(json[:invoice][:contracts].map { it[:lago_id] }).to eq([contract_rate_card.contract_id])
      expect(json[:invoice]).to include(applied_invoice_custom_sections: [], error_details: [])
    end

    context "with more fees than an expansion holds" do
      let(:names) { %w[fees] }

      before do
        stub_const("#{described_class}::MAX_EXPANDED_FEES", 1)
        create(:fee, fee_attributes)
      end

      it "points to the fee list instead" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          status: 400,
          error: "Bad Request",
          code: "expansion_too_large",
          error_details: {expands: {fees: {count: 2, max: 1}}}
        )
      end

      context "when the fees are not requested" do
        let(:names) { %w[applied_taxes] }

        it "returns the invoice" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:invoice]).not_to have_key(:fees)
        end
      end
    end

    context "when a catalog invoice of another type also holds a legacy fee" do
      let(:contract_invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription) }
      let(:names) { %w[fees] }

      before do
        stub_const("#{described_class}::MAX_EXPANDED_FEES", 1)
        create(:fee, invoice: contract_invoice)
      end

      it "counts and expands its product fees only" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:invoice][:fees].map { it[:lago_id] }).to eq([fee.id])
      end
    end

    context "with a name the invoice does not declare" do
      let(:names) { %w[fees subscriptions] }

      it "returns an invalid_expand error listing the invoice expansions" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details][:expands]).to include(invalid_values: %w[subscriptions])
      end
    end

    context "when listing invoices" do
      subject { get_with_token(organization, "/api/v2/invoices", {expands: %w[fees], limit: 0}) }

      it "refuses the expansion before reading the pagination" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: %w[fees]})
      end
    end

    context "when voiding the invoice" do
      subject { post_with_token(organization, "/api/v2/invoices/#{contract_invoice.id}/void?expands[]=fees") }

      it "refuses the expansion before voiding it" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(contract_invoice.reload).to be_finalized
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }
      let(:names) { %w[bogus] }

      it "validates the expansion before looking up the invoice" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
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
