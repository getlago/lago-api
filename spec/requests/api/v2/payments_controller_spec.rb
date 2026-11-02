# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PaymentsController do
  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: ["product_catalog"]) }

  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :finalized, organization:, customer:, invoice_type: :contract, total_amount_cents: 1_000) }
  let(:payment) { create(:payment, organization:, payable: invoice) }

  describe "GET /api/v2/payments" do
    subject(:request) { get_with_token(organization, "/api/v2/payments", params) }

    let(:params) { {} }

    before do
      payment
      create(:payment, payable: create(:invoice, organization: create(:organization)))
    end

    include_examples "requires API permission", "payment", "read"

    it "returns the organization's payments with the flat v2 payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:payments].sole).to eq(
        lago_id: payment.id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        lago_payable_id: invoice.id,
        payable_type: "Invoice",
        lago_invoice_ids: [invoice.id],
        amount_cents: payment.amount_cents,
        currency: payment.amount_currency,
        status: payment.status,
        payment_status: payment.payable_payment_status,
        payment_type: payment.payment_type,
        reference: nil,
        payment_provider_code: payment.payment_provider.code,
        payment_provider_type: "stripe",
        provider_payment_id: payment.provider_payment_id,
        provider_customer_id: payment.payment_provider_customer.provider_customer_id,
        next_action: {},
        created_at: payment.created_at.iso8601(6),
        updated_at: payment.updated_at.iso8601(6)
      )
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "with a legacy invoice" do
      let(:invoice) { create(:invoice, :finalized, organization:, customer:) }

      it "still returns its payment" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payments].sole[:lago_invoice_ids]).to eq([invoice.id])
      end
    end

    context "with a payment request", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
      let(:other_invoice) { create(:invoice, :finalized, organization:, customer:, invoice_type: :contract) }
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice, other_invoice]) }
      let(:payment) { create(:payment, organization:, payable: payment_request) }

      before do
        create(:payment, payable: create(:payment_request, organization:, customer:, invoices: [other_invoice]))
      end

      it "includes the invoices covered by each request" do
        request

        expect(response).to have_http_status(:ok)
        serialized_payment = json[:payments].find { it[:lago_id] == payment.id }
        expect(serialized_payment).to include(lago_payable_id: payment_request.id, payable_type: "PaymentRequest")
        expect(serialized_payment[:lago_invoice_ids]).to match_array([invoice.id, other_invoice.id])
      end
    end

    context "with the external_customer_id filter" do
      let(:params) { {external_customer_id: customer.external_id} }

      before { create(:payment, payable: create(:invoice, organization:)) }

      it "returns only the customer's payments" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payments].map { it[:lago_id] }).to eq([payment.id])
      end
    end

    context "with the invoice_id filter" do
      let(:params) { {invoice_id: invoice.id} }
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice]) }
      let(:request_payment) { create(:payment, organization:, payable: payment_request) }

      before do
        request_payment
        create(:payment, payable: create(:invoice, organization:))
      end

      it "includes direct payments and payments on a request covering the invoice" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payments].map { it[:lago_id] }).to match_array([payment.id, request_payment.id])
      end
    end

    context "with an invalid invoice_id filter" do
      let(:params) { {invoice_id: "invalid"} }

      it "returns a validation error" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "invoice_id", meta: {}}])
      end
    end

    context "with no matching customer" do
      let(:params) { {external_customer_id: "unknown"} }

      it "returns an empty page" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payments]).to eq([])
        expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
      end
    end

    Invoice::INVISIBLE_STATUS.each_key do |status|
      context "with a #{status} invoice" do
        let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }

        it "does not list its payment" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:payments]).to eq([])
        end
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :payments, model: Payment do
      let(:paginated_path) { "/api/v2/payments" }
      let(:create_paginated_record) { ->(created_at) { create(:payment, payable: create(:invoice, organization:), created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :payments do
      let(:filtered_path) { "/api/v2/payments" }
      let(:create_filtered_record) { ->(created_at) { create(:payment, payable: create(:invoice, organization:), created_at:) } }
    end
  end

  describe "GET /api/v2/payments/:id" do
    subject(:request) { get_with_token(organization, "/api/v2/payments/#{payment_id}") }

    let(:payment_id) { payment.id }

    include_examples "requires API permission", "payment", "read"

    it "returns the payment with v2 names and timestamps" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:payment]).to eq(
        lago_id: payment.id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        lago_payable_id: invoice.id,
        payable_type: "Invoice",
        lago_invoice_ids: [invoice.id],
        amount_cents: payment.amount_cents,
        currency: payment.amount_currency,
        status: payment.status,
        payment_status: payment.payable_payment_status,
        payment_type: "provider",
        reference: nil,
        payment_provider_code: payment.payment_provider.code,
        payment_provider_type: "stripe",
        provider_payment_id: payment.provider_payment_id,
        provider_customer_id: payment.payment_provider_customer.provider_customer_id,
        next_action: {},
        created_at: payment.created_at.iso8601(6),
        updated_at: payment.updated_at.iso8601(6)
      )
    end

    context "with a payment request" do
      let(:other_invoice) { create(:invoice, :finalized, organization:, customer:) }
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice, other_invoice]) }
      let(:payment) { create(:payment, organization:, payable: payment_request) }

      it "returns all invoice references" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment][:lago_invoice_ids]).to match_array([invoice.id, other_invoice.id])
      end
    end

    context "with a missing payment" do
      let(:payment_id) { SecureRandom.uuid }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("payment")
      end
    end

    context "with another organization's payment" do
      let(:payment) { create(:payment, payable: create(:invoice, organization: create(:organization))) }

      it "does not expose it" do
        request

        expect(response).to be_v2_not_found_error("payment")
      end
    end

    context "when the payment belongs to another organization but its invoice does not" do
      let(:payment) { create(:payment, organization: create(:organization), payable: invoice) }

      it "does not expose the foreign payment" do
        request

        expect(response).to be_v2_not_found_error("payment")
      end
    end

    context "when the invoice belongs to another organization but its payment does not" do
      let(:invoice) { create(:invoice, organization: create(:organization)) }

      it "does not expose a payment linked to a foreign invoice" do
        request

        expect(response).to be_v2_not_found_error("payment")
      end
    end

    Invoice::INVISIBLE_STATUS.each_key do |status|
      context "with a #{status} invoice" do
        let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }

        it "does not expose its payment" do
          request

          expect(response).to be_v2_not_found_error("payment")
        end
      end
    end
  end

  describe "POST /api/v2/payments", :premium do
    subject(:request) { post_with_token(organization, "/api/v2/payments", {payment: attributes}) }

    let(:attributes) { {invoice_id: invoice.id, amount_cents:, reference: "bank-transfer", paid_at:} }
    let(:amount_cents) { 1_000 }
    let(:paid_at) { "2026-10-01T12:00:00.123456Z" }

    include_examples "requires API permission", "payment", "write"

    it "records a manual payment and settles the catalog invoice" do
      expect { request }.to change(invoice.payments, :count).by(1)

      expect(response).to have_http_status(:ok)
      recorded_payment = invoice.payments.sole
      expect(recorded_payment).to have_attributes(
        organization_id: organization.id,
        customer_id: customer.id,
        amount_cents:,
        amount_currency: invoice.currency,
        payment_type: "manual",
        reference: "bank-transfer",
        payable_payment_status: "succeeded"
      )
      expect(invoice.reload).to have_attributes(total_paid_amount_cents: amount_cents, payment_status: "succeeded")
      expect(json[:payment]).to include(
        lago_id: recorded_payment.id,
        lago_invoice_ids: [invoice.id],
        currency: invoice.currency,
        payment_type: "manual",
        payment_provider_code: nil,
        created_at: paid_at,
        updated_at: recorded_payment.updated_at.iso8601(6)
      )
      expect(json[:payment]).not_to have_key(:amount_currency)
    end

    context "with a partial payment" do
      let(:amount_cents) { 400 }

      it "updates the paid amount without marking the invoice paid" do
        request

        expect(response).to have_http_status(:ok)
        expect(invoice.reload).to have_attributes(total_paid_amount_cents: 400, payment_status: "pending")
      end
    end

    context "with a legacy invoice" do
      let(:invoice) { create(:invoice, :finalized, organization:, customer:, total_amount_cents: 1_000) }

      it "still records its payment" do
        request

        expect(response).to have_http_status(:ok)
        expect(invoice.reload).to have_attributes(total_paid_amount_cents: 1_000, payment_status: "succeeded")
      end
    end

    context "with a supplied currency" do
      let(:attributes) { super().merge(currency: "USD", amount_currency: "USD") }

      it "uses the invoice currency instead" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment][:currency]).to eq(invoice.currency)
        expect(invoice.payments.sole.amount_currency).to eq(invoice.currency)
      end
    end

    context "when receipts are enabled" do
      before { organization.update!(premium_integrations: ["issue_receipts"]) }

      it "creates a receipt through the receipt job" do
        expect do
          perform_enqueued_jobs(only: [PaymentReceipts::CreateJob]) { request }
        end.to change(PaymentReceipt, :count).by(1)

        expect(response).to have_http_status(:ok)
        receipt = organization.payment_receipts.find_by!(payment_id: json[:payment][:lago_id])
        expect(receipt.billing_entity_id).to eq(invoice.billing_entity_id)
      end
    end

    context "when receipts are disabled" do
      before { organization.update!(premium_integrations: []) }

      it "does not enqueue a receipt job" do
        expect { request }.not_to have_enqueued_job(PaymentReceipts::CreateJob)

        expect(response).to have_http_status(:ok)
      end
    end

    context "with another organization's invoice" do
      let(:invoice) { create(:invoice, :finalized, organization: create(:organization), invoice_type: :contract, total_amount_cents: 1_000) }

      it "does not create a payment or change the invoice" do
        expect { request }.not_to change(Payment, :count)

        expect(response).to be_v2_not_found_error("invoice")
        expect(invoice.reload).to have_attributes(total_paid_amount_cents: 0, payment_status: "pending")
      end
    end

    context "with a missing invoice" do
      let(:attributes) { super().merge(invoice_id: SecureRandom.uuid) }

      it "returns not found" do
        expect { request }.not_to change(Payment, :count)

        expect(response).to be_v2_not_found_error("invoice")
      end
    end

    context "without an invoice_id" do
      let(:attributes) { super().except(:invoice_id) }

      it "returns the existing required invoice validation" do
        expect { request }.not_to change(Payment, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "invoice_id", meta: {}}])
      end
    end

    context "with a draft invoice" do
      let(:invoice) { create(:invoice, :draft, organization:, customer:, invoice_type: :contract) }

      it "keeps the existing manual-payment restriction" do
        expect { request }.not_to change(Payment, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with an overpayment" do
      let(:amount_cents) { 1_001 }

      it "returns a validation error without changing the invoice" do
        expect { request }.not_to change(Payment, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_out_of_range", field: "amount_cents", meta: {}}])
        expect(invoice.reload.total_paid_amount_cents).to eq(0)
      end
    end

    [nil, 0, -1, "100", 1.5].each do |invalid_amount|
      context "with amount_cents #{invalid_amount.inspect}" do
        let(:amount_cents) { invalid_amount }

        it "returns a validation error" do
          expect { request }.not_to change(Payment, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "invalid_value", field: "amount_cents", meta: {}}])
        end
      end
    end

    context "without a reference" do
      let(:attributes) { super().except(:reference) }

      it "keeps the existing required reference validation" do
        expect { request }.not_to change(Payment, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "reference", meta: {}}])
      end
    end

    %i[contract advance_charges].each do |invoice_type|
      context "with an invalid date on a #{invoice_type} invoice" do
        let(:invoice) { create(:invoice, :finalized, organization:, customer:, invoice_type:, total_amount_cents: 1_000) }
        let(:paid_at) { "invalid_date" }

        it "rejects the date without creating a payment" do
          expect { request }.not_to change(Payment, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "invalid_date", field: "paid_at", meta: {}}])
        end
      end
    end

    [nil, ""].each do |blank_date|
      context "with paid_at #{blank_date.inspect}" do
        let(:paid_at) { blank_date }

        it "defaults the payment timestamp to now" do
          freeze_time do
            request

            expect(response).to have_http_status(:ok)
            expect(json[:payment][:created_at]).to eq(Time.current.iso8601(6))
          end
        end
      end
    end

    [nil, "invalid", ["invalid"]].each do |body|
      context "with a malformed payment wrapper #{body.inspect}" do
        subject(:request) { post_with_token(organization, "/api/v2/payments", {payment: body}) }

        it "returns the v2 missing parameter error" do
          expect { request }.not_to change(Payment, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "payment", meta: {}}])
        end
      end
    end
  end

  [[:get, "/api/v2/payments"], [:get, "/api/v2/payments/unknown"], [:post, "/api/v2/payments"]].each do |method, path|
    describe "#{method.upcase} #{path} access and expansions" do
      subject(:request) { public_send(:"#{method}_with_token", organization, path, params) }

      let(:params) { {} }

      context "when the organization is not on the product catalog", product_catalog: false do
        let(:organization) { create(:organization) }

        it "returns a forbidden error" do
          request

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end

      context "without authentication" do
        it "returns unauthorized" do
          public_send(method, path, params:)

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context "with expands" do
        let(:params) { {expands: ["customer"]} }

        it "rejects the unsupported expansion" do
          expect { request }.not_to change(Payment, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("expand_not_supported")
        end
      end
    end
  end
end
