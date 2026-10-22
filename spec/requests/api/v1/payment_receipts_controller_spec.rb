# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PaymentReceiptsController do
  let(:organization) { create(:organization) }

  describe "GET /api/v1/payment_receipts" do
    subject { get_with_token(organization, "/api/v1/payment_receipts", params) }

    let(:params) { {} }

    include_examples "requires API permission", "invoice", "read"

    it "returns organization's payments" do
      invoice = create(:invoice, organization:)
      invoice2 = create(:invoice, organization:)
      payment_request = create(:payment_request, organization:)
      first_payment = create(:payment, payable: invoice)
      second_payment = create(:payment, payable: invoice2)
      third_payment = create(:payment, payable: payment_request)

      first_payment_receipt = create(:payment_receipt, payment: first_payment, organization:)
      second_payment_receipt = create(:payment_receipt, payment: second_payment, organization:)
      third_payment_receipt = create(:payment_receipt, payment: third_payment, organization:)
      create(:payment_receipt)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_receipts].count).to eq(3)
      expect(json[:payment_receipts].map { |r| r[:lago_id] }).to contain_exactly(
        first_payment_receipt.id,
        second_payment_receipt.id,
        third_payment_receipt.id
      )
    end

    context "with a not found invoice" do
      let(:params) { {invoice_id: SecureRandom.uuid} }

      before do
        invoice = create(:invoice, organization:)
        payment = create(:payment, payable: invoice)
        create(:payment_receipt, payment:)
      end

      it "returns an empty result" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payment_receipts]).to be_empty
      end
    end

    context "with invoice" do
      let(:invoice) { create(:invoice, organization:) }
      let(:invoice2) { create(:invoice, organization:) }
      let(:params) { {invoice_id: invoice.id} }
      let(:first_payment) { create(:payment, payable: invoice) }
      let(:first_payment_receipt) { create(:payment_receipt, payment: first_payment, organization:) }

      let(:second_payment) { create(:payment, payable: invoice2) }

      before do
        first_payment_receipt
        create(:payment_receipt, payment: second_payment)
      end

      it "returns invoices's payment receipts" do
        subject
        expect(response).to have_http_status(:success)
        expect(json[:payment_receipts].map { |r| r[:lago_id] }).to contain_exactly(first_payment_receipt.id)
        expect(json[:payment_receipts].first[:payment][:invoice_ids].first).to eq(invoice.id)
      end
    end

    context "when an older receipt's payment references an invoice that no longer exists" do
      let(:customer) { create(:customer, organization:) }
      let(:valid_invoice) { create(:invoice, customer:, organization:) }
      let(:valid_payment) { create(:payment, payable: valid_invoice) }
      let!(:valid_receipt) { create(:payment_receipt, payment: valid_payment, organization:) }

      let(:missing_invoice_id) { SecureRandom.uuid }
      let(:orphan_payment) { create(:payment, payable: create(:invoice, customer:, organization:)) }
      let!(:orphan_receipt) do
        create(:payment_receipt, payment: orphan_payment, organization:, created_at: 2.days.ago)
      end

      before { orphan_payment.update_columns(payable_id: missing_invoice_id) } # rubocop:disable Rails/SkipsModelValidations

      context "without pagination params" do
        it "returns both receipts" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:payment_receipts].map { |r| r[:lago_id] }).to eq([valid_receipt.id, orphan_receipt.id])
        end

        it "serializes the payment from its own data" do
          subject

          orphan = json[:payment_receipts].find { |r| r[:lago_id] == orphan_receipt.id }
          expect(orphan[:number]).to eq(orphan_receipt.number)
          expect(orphan[:payment]).to include(
            lago_id: orphan_payment.id,
            lago_customer_id: customer.id,
            external_customer_id: customer.external_id,
            invoice_ids: [],
            invoice_numbers: [],
            lago_payable_id: missing_invoice_id,
            payable_type: "Invoice",
            amount_cents: orphan_payment.amount_cents,
            amount_currency: orphan_payment.amount_currency
          )
        end
      end

      context "with per_page=1" do
        let(:params) { {per_page: 1} }

        it "returns the most recent receipt" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:payment_receipts].map { |r| r[:lago_id] }).to eq([valid_receipt.id])
        end
      end

      context "with per_page=5" do
        let(:params) { {per_page: 5} }

        it "returns both receipts" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:payment_receipts].map { |r| r[:lago_id] }).to eq([valid_receipt.id, orphan_receipt.id])
        end
      end
    end
  end

  describe "GET /api/v1/payment_receipts/:id" do
    subject { get_with_token(organization, "/api/v1/payment_receipts/#{id}") }

    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:payment) { create(:payment, payable: invoice) }
    let(:payment_receipt) { create(:payment_receipt, payment:, organization:) }

    context "when payment receipt exists" do
      let(:id) { payment_receipt.id }

      include_examples "requires API permission", "invoice", "read"

      it "returns the payment receipt" do
        subject
        expect(response).to have_http_status(:ok)
        expect(json[:payment_receipt][:lago_id]).to eq(payment_receipt.id)
        expect(json[:payment_receipt][:payment][:invoice_ids].first).to eq(invoice.id)
      end
    end

    context "when payment for a payment request exists" do
      let(:payment_request) { create(:payment_request, customer:, organization:, invoices: [invoice]) }
      let(:payment) { create(:payment, payable: payment_request) }
      let(:payment_receipt) { create(:payment_receipt, payment:, organization:) }
      let(:id) { payment_receipt.id }

      include_examples "requires API permission", "invoice", "read"

      it "returns the payment receipt" do
        subject
        expect(response).to have_http_status(:ok)
        expect(json[:payment_receipt][:lago_id]).to eq(payment_receipt.id)
        expect(json[:payment_receipt][:payment][:invoice_ids].first).to eq(invoice.id)
      end
    end

    context "when the payment references an invoice that no longer exists" do
      let(:missing_invoice_id) { SecureRandom.uuid }
      let(:id) { payment_receipt.id }

      before { payment.update_columns(payable_id: missing_invoice_id) } # rubocop:disable Rails/SkipsModelValidations

      it "returns the payment receipt" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:payment_receipt][:lago_id]).to eq(payment_receipt.id)
        expect(json[:payment_receipt][:payment]).to include(
          lago_id: payment.id,
          lago_customer_id: customer.id,
          external_customer_id: customer.external_id,
          invoice_ids: [],
          invoice_numbers: [],
          lago_payable_id: missing_invoice_id
        )
      end
    end

    context "when payment does not exist" do
      let(:id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/payment_receipts/:id/resend_email" do
    subject { post_with_token(organization, "/api/v1/payment_receipts/#{payment_receipt.id}/resend_email", {}) }

    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:payment) { create(:payment, payable: invoice) }
    let(:payment_receipt) { create(:payment_receipt, payment:, organization:) }

    context "when the payment references an invoice that no longer exists" do
      before { payment.update_columns(payable_id: SecureRandom.uuid) } # rubocop:disable Rails/SkipsModelValidations

      it "returns a controlled error without enqueueing the email" do
        expect { subject }.not_to have_enqueued_mail(PaymentReceiptMailer, :created)

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("payable_not_found")
      end
    end
  end
end
