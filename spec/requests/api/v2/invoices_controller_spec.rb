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

    let(:invoice) { create(:invoice, status:, payment_status: :pending, customer:, organization:, invoice_type: :contract) }
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
      expect(json[:invoice]).to include(lago_id: invoice.id, status: "voided", invoice_type: "contract")
      expect(json[:invoice]).not_to include(:subscriptions, :fees)
    end

    context "when the invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error without voiding it" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(legacy_invoice.reload).to be_finalized
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

  describe "POST /api/v2/invoices/:id/download_pdf" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/download_pdf") }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }

    include_examples "requires API permission", "invoice", "write"

    it "generates the pdf asynchronously" do
      subject

      expect(response).to have_http_status(:success)
      expect(response.body).to be_empty
      expect(Invoices::GeneratePdfJob).to have_been_enqueued.with(invoice)
    end

    context "when the pdf is already generated" do
      before do
        invoice.file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
          filename: "invoice.pdf",
          content_type: "application/pdf"
        )
      end

      it "returns the invoice without regenerating it" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(lago_id: invoice.id, invoice_type: "contract")
        expect(json[:invoice][:pdf_url]).to be_present
        expect(json[:invoice]).not_to have_key(:fees)
        expect(Invoices::GeneratePdfJob).not_to have_been_enqueued
      end
    end

    context "when the invoice is a draft" do
      let(:status) { :draft }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(Invoices::GeneratePdfJob).not_to have_been_enqueued
      end
    end
  end

  describe "POST /api/v2/invoices/:id/resend_email" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/resend_email", params) }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status: :finalized, fees_amount_cents: 1_000) }
    let(:invoice_id) { invoice.id }
    let(:params) { {to: ["custom@example.com"], cc: ["cc@example.com"], bcc: ["bcc@example.com"]} }

    before { customer.billing_entity.update!(email: "billing@example.com") }

    include_examples "requires API permission", "invoice", "write"

    it "resends the invoice email", :premium do
      expect { subject }.to have_enqueued_mail(InvoiceMailer, :created)
        .with(params: {invoice:, resend: true, to: ["custom@example.com"], cc: ["cc@example.com"], bcc: ["bcc@example.com"]}, args: [])

      expect(response).to have_http_status(:success)
      expect(response.body).to be_empty
    end

    context "without a premium license" do
      it "returns a forbidden error" do
        expect { subject }.not_to have_enqueued_mail(InvoiceMailer, :created)

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("premium_license_required")
      end
    end

    context "when the invoice is a legacy one", :premium do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        expect { subject }.not_to have_enqueued_mail(InvoiceMailer, :created)

        expect(response).to be_not_found_error("invoice")
      end
    end
  end

  describe "POST /api/v2/invoices/:id/retry" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/retry") }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :failed }

    include_examples "requires API permission", "invoice", "write"

    it "reopens the failed invoice and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(invoice.reload).to be_pending
      expect(json[:invoice]).to include(lago_id: invoice.id, status: "pending", invoice_type: "contract")
      expect(json[:invoice]).not_to have_key(:fees)
      expect(Invoices::ProviderTaxes::PullTaxesAndApplyJob).to have_been_enqueued.with(invoice:)
    end

    context "when the invoice is not failed" do
      let(:status) { :finalized }

      it "returns a method not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("invalid_status")
        expect(invoice.reload).to be_finalized
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(Invoices::ProviderTaxes::PullTaxesAndApplyJob).not_to have_been_enqueued
      end
    end
  end

  describe "POST /api/v2/invoices/:id/retry_payment" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/retry_payment", params) }

    let(:invoice_id) { contract_invoice.id }
    let(:params) { {payment_method: {payment_method_type: "manual"}} }
    let(:retry_result) { Invoices::Payments::RetryService::Result.new }

    before { allow(Invoices::Payments::RetryService).to receive(:call).and_return(retry_result) }

    include_examples "requires API permission", "invoice", "write"

    it "retries the payment with the given payment method" do
      subject

      expect(response).to have_http_status(:success)
      expect(response.body).to be_empty
      expect(Invoices::Payments::RetryService).to have_received(:call)
        .with(invoice: contract_invoice, payment_method_params: {payment_method_type: "manual"})
    end

    context "when the payment cannot be retried" do
      let(:retry_result) { Invoices::Payments::RetryService::Result.new.not_allowed_failure!(code: "invalid_status") }

      it "returns a method not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("invalid_status")
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(Invoices::Payments::RetryService).not_to have_received(:call)
      end
    end
  end

  describe "POST /api/v2/invoices/:id/payment_url" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/payment_url") }

    let(:customer) { create(:customer, organization:, payment_provider: "stripe", payment_provider_code: stripe_provider.code) }
    let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_1") }
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }

    before do
      create(:stripe_customer, customer:, payment_provider: stripe_provider)
      allow(::Stripe::Checkout::Session).to receive(:create).and_return({"url" => "https://example.com"})
    end

    include_examples "requires API permission", "invoice", "write"

    it "returns the generated payment url" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_payment_details]).to eq(
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        payment_provider: "stripe",
        lago_invoice_id: invoice.id,
        payment_url: "https://example.com"
      )
    end

    context "when the invoice is a draft" do
      let(:status) { :draft }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details]).to eq(base: ["invalid_invoice_status_or_payment_status"])
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(::Stripe::Checkout::Session).not_to have_received(:create)
      end
    end
  end

  describe "PUT /api/v2/invoices/:id/finalize" do
    subject { put_with_token(organization, "/api/v2/invoices/#{invoice_id}/finalize") }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :draft }
    let(:finalize_result) { Invoices::RefreshDraftAndFinalizeService::Result.new.tap { it.invoice = invoice } }

    before { allow(Invoices::RefreshDraftAndFinalizeService).to receive(:call).and_return(finalize_result) }

    include_examples "requires API permission", "invoice", "write"

    it "finalizes the draft and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(lago_id: invoice.id, invoice_type: "contract")
      expect(json[:invoice]).not_to have_key(:fees)
      expect(Invoices::RefreshDraftAndFinalizeService).to have_received(:call).with(invoice:)
    end

    context "when the invoice cannot be finalized" do
      let(:finalize_result) { Invoices::RefreshDraftAndFinalizeService::Result.new.forbidden_failure!(code: "cannot_finalize_with_pending_taxes") }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("cannot_finalize_with_pending_taxes")
      end
    end

    context "when the invoice is not a draft" do
      let(:status) { :finalized }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(Invoices::RefreshDraftAndFinalizeService).not_to have_received(:call)
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { create(:invoice, :draft, organization:, customer:).id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(Invoices::RefreshDraftAndFinalizeService).not_to have_received(:call)
      end
    end
  end

  describe "PUT /api/v2/invoices/:id/refresh" do
    subject { put_with_token(organization, "/api/v2/invoices/#{invoice_id}/refresh") }

    let(:invoice) { create(:invoice, :draft, organization:, customer:, invoice_type: :contract) }
    let(:invoice_id) { invoice.id }
    let(:refresh_result) { Invoices::RefreshDraftService::Result.new.tap { it.invoice = invoice } }

    before { allow(Invoices::RefreshDraftService).to receive(:call).and_return(refresh_result) }

    include_examples "requires API permission", "invoice", "write"

    it "refreshes the draft and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(lago_id: invoice.id, invoice_type: "contract", status: "draft")
      expect(json[:invoice]).not_to have_key(:fees)
      expect(Invoices::RefreshDraftService).to have_received(:call).with(invoice:)
    end

    context "when the invoice cannot be refreshed" do
      let(:refresh_result) { Invoices::RefreshDraftService::Result.new.forbidden_failure! }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(Invoices::RefreshDraftService).not_to have_received(:call)
      end
    end
  end

  describe "PUT /api/v2/invoices/:id" do
    subject { put_with_token(organization, "/api/v2/invoices/#{invoice_id}", {invoice: {payment_status: "succeeded"}}) }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:invoice_id) { invoice.id }

    include_examples "requires API permission", "invoice", "write"

    it "updates the payment status and returns the invoice" do
      subject

      expect(response).to have_http_status(:success)
      expect(invoice.reload).to be_payment_succeeded
      expect(json[:invoice]).to include(lago_id: invoice.id, invoice_type: "contract", payment_status: "succeeded", fees: [])
    end

    context "when the invoice is voided" do
      let(:invoice) { create(:invoice, :voided, organization:, customer:, invoice_type: :contract) }

      it "returns a method not allowed error without updating it" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("update_on_voided_invoice")
        expect(invoice.reload).to be_payment_pending
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error without updating it" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(legacy_invoice.reload).to be_payment_pending
      end
    end
  end

  describe "DELETE /api/v2/invoices/:id" do
    subject { delete_with_token(organization, "/api/v2/invoices/#{invoice_id}") }

    let(:invoice) { create(:invoice, :draft, organization:, customer:, invoice_type: :contract) }
    let(:invoice_id) { invoice.id }

    include_examples "requires API permission", "invoice", "write"

    it "deletes the draft and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(invoice.reload).to be_deleted
      expect(json[:invoice]).to include(lago_id: invoice.id, invoice_type: "contract", status: "deleted")
    end

    context "when the invoice is finalized" do
      let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }

      it "returns a method not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("not_deletable")
        expect(invoice.reload).to be_finalized
      end
    end

    context "when the invoice is a legacy one" do
      let(:legacy_invoice) { create(:invoice, :draft, organization:, customer:) }
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error without deleting it" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(legacy_invoice.reload).to be_draft
      end
    end
  end

  describe "POST /api/v2/invoices/:id/lose_dispute" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/lose_dispute") }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:invoice_id) { invoice.id }

    include_examples "requires API permission", "invoice", "write"

    it "marks the dispute as lost and returns the invoice" do
      freeze_time do
        subject

        expect(response).to have_http_status(:success)
        expect(invoice.reload.payment_dispute_lost_at).to eq(Time.current)
        expect(json[:invoice]).to include(lago_id: invoice.id, payment_dispute_lost_at: Time.current.iso8601)
      end
    end

    context "when the invoice is a draft" do
      let(:invoice) { create(:invoice, :draft, organization:, customer:, invoice_type: :contract) }

      it "returns a method not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("not_disputable")
        expect(invoice.reload.payment_dispute_lost_at).to be_nil
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error without marking it" do
        subject

        expect(response).to be_not_found_error("invoice")
        expect(legacy_invoice.reload.payment_dispute_lost_at).to be_nil
      end
    end
  end

  describe "POST /api/v2/invoices/:id/retry_taxes" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice.id}/retry_taxes") }

    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status: :failed) }

    include_examples "requires API permission", "invoice", "write"

    it "retries the failed invoice like retry" do
      subject

      expect(response).to have_http_status(:success)
      expect(invoice.reload).to be_pending
      expect(Invoices::ProviderTaxes::PullTaxesAndApplyJob).to have_been_enqueued.with(invoice:)
    end
  end

  describe "POST /api/v2/invoices/:id/x402_payment_url", :premium do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/x402_payment_url", {connection_code: connection.code}) }

    let(:organization) { create(:organization, feature_flags: %w[product_catalog x402_payments]) }
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, currency: "USD", total_amount_cents: 1_000) }
    let(:invoice_id) { invoice.id }
    let(:connection) { create(:x402_connection, organization:) }

    before { create(:wallet, customer:, currency: "USD", x402_enabled: true) }

    include_examples "requires API permission", "invoice", "write"

    it "returns the payment url bound to the connection" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_x402_payment_details]).to eq(
        lago_invoice_id: invoice.id,
        x402_connection_code: connection.code,
        x402_payment_url: invoice.reload.x402_payment_url
      )
    end

    context "without x402 payments" do
      let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000).id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end
  end
end
