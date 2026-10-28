# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceiptMailer do
  subject(:payment_receipt_mailer) { described_class }

  let(:payment_receipt) { create(:payment_receipt) }
  let(:invoice) { payment_receipt.payment.payable }

  before do
    payment_receipt.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "blank.pdf")
    invoice.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "blank.pdf")
    allow(payment_receipt.payment.payable).to receive(:file_url).and_return("https://example.com/invoice.pdf")
  end

  describe "#created" do
    specify do
      mailer = payment_receipt_mailer.with(payment_receipt:).created

      expect(mailer.to).to eq([payment_receipt.payment.payable.customer.email])
      expect(mailer.reply_to).to eq([payment_receipt.billing_entity.email])
      expect(mailer.attachments).not_to be_empty
      expect(mailer.attachments.first.filename).to eq("receipt-#{payment_receipt.number}.pdf")
    end

    context "when the receipt pays a catalog invoice" do
      let(:organization) { create(:organization, :with_static_values) }
      let(:customer) { create(:customer, :with_static_values, organization:) }
      let(:invoice) do
        create(:invoice, organization:, customer:, invoice_type:, status: :finalized, currency: "EUR",
          fees_amount_cents: 2_800, sub_total_excluding_taxes_amount_cents: 2_800,
          sub_total_including_taxes_amount_cents: 2_800, total_amount_cents: 2_800, total_paid_amount_cents: 2_800)
      end
      let(:contract) { create(:contract, organization:, customer:) }
      let(:category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
      let(:product) { create(:product, organization:, product_category: category, name: "Compute", invoice_display_name: nil) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:)) }
      let(:payment) do
        create(:payment, payable: invoice, organization:, customer:, amount_cents: 2_800, amount_currency: "EUR", status: "succeeded")
      end
      let(:payment_receipt) { create(:payment_receipt, payment:, organization:) }
      let(:generate_invoice_pdf) { true }

      before do
        payment_receipt.file.purge
        invoice.file.purge
        allow(invoice).to receive(:file_url).and_call_original
        create(:fee, invoice:, subscription: nil, fee_type: :product, invoiceable: product,
          invoice_display_name: nil, contract:, contract_rate_card:,
          rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
          amount_cents: 2_800, amount_currency: "EUR", units: 280, precise_unit_amount: BigDecimal("0.1"),
          properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"})
        stub_pdf_generation
        Invoices::GeneratePdfService.call!(invoice:) if generate_invoice_pdf
      end

      shared_examples "a delivered catalog receipt" do
        it "generates the receipt and delivers both rendered documents" do
          mail = payment_receipt_mailer.with(payment_receipt:).created.deliver_now

          expect(ActionMailer::Base.deliveries).to include(mail)
          expect(mail.to).to eq([customer.email])
          expect(mail.attachments.map(&:filename)).to eq(["receipt-#{payment_receipt.number}.pdf", "invoice-#{invoice.number}.pdf"])
          expect(payment_receipt.reload.file).to be_attached
          expect(mail.attachments["receipt-#{payment_receipt.number}.pdf"].body.decoded).to include("Infrastructure")
          expect(mail.attachments["invoice-#{invoice.number}.pdf"].body.decoded).to include("Infrastructure")
        end

        context "when the invoice PDF is not ready" do
          let(:generate_invoice_pdf) { false }

          it "refuses delivery until the underlying invoice PDF is available" do
            expect {
              payment_receipt_mailer.with(payment_receipt:).created.deliver_now
            }.to raise_error(PaymentReceipts::FilesNotReadyError)
            expect(ActionMailer::Base.deliveries).to be_empty
          end
        end
      end

      context "with a contract invoice" do
        let(:invoice_type) { :contract }

        include_examples "a delivered catalog receipt"
      end

      context "with an advance charges invoice" do
        let(:invoice_type) { :advance_charges }

        include_examples "a delivered catalog receipt"
      end
    end

    context "when pdfs are disabled" do
      around do |example|
        ENV["LAGO_DISABLE_PDF_GENERATION"] = "true"
        example.run
        ENV.delete("LAGO_DISABLE_PDF_GENERATION")
      end

      it "does not attach the pdf" do
        mailer = payment_receipt_mailer.with(payment_receipt:).created

        expect(mailer.attachments).to be_empty
      end
    end

    context "when the payment receipt file is still missing after generation" do
      let(:pdf_service) { instance_double(PaymentReceipts::GeneratePdfService, call: nil) }

      before do
        payment_receipt.file.purge
        allow(PaymentReceipts::GeneratePdfService).to receive(:new).and_return(pdf_service)
      end

      it "raises FilesNotReadyError" do
        expect {
          payment_receipt_mailer.with(payment_receipt:).created.deliver_now
        }.to raise_error(PaymentReceipts::FilesNotReadyError)

        expect(PaymentReceipts::GeneratePdfService).to have_received(:new)
      end
    end

    context "when an invoice file is missing" do
      before { invoice.file.purge }

      it "raises FilesNotReadyError" do
        expect {
          payment_receipt_mailer.with(payment_receipt:).created.deliver_now
        }.to raise_error(PaymentReceipts::FilesNotReadyError)
      end
    end

    context "when the payment is for a payment request covering multiple invoices" do
      let(:other_invoice) { create(:invoice, organization: invoice.organization, customer: invoice.customer) }
      let(:payment_request) do
        create(:payment_request, organization: invoice.organization, customer: invoice.customer, invoices: [invoice, other_invoice])
      end

      before do
        payment_receipt.payment.update!(payable: payment_request)
        allow(other_invoice).to receive(:file_url).and_return("https://example.com/other.pdf")
      end

      context "when every invoice has a file attached" do
        before do
          other_invoice.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "blank.pdf")
        end

        it "renders the email" do
          mailer = payment_receipt_mailer.with(payment_receipt:).created

          expect(mailer.to).to eq([payment_request.customer.email])
        end
      end

      context "when one invoice in the request is missing its file" do
        it "raises FilesNotReadyError" do
          expect {
            payment_receipt_mailer.with(payment_receipt:).created.deliver_now
          }.to raise_error(PaymentReceipts::FilesNotReadyError)
        end
      end
    end

    context "when billing entity email is nil" do
      before do
        payment_receipt.billing_entity.update(email: nil)
      end

      it "returns a mailer with nil values" do
        mailer = payment_receipt_mailer.with(payment_receipt:).created

        expect(mailer.to).to be_nil
      end
    end

    context "when customer email is nil" do
      before do
        payment_receipt.payment.payable.customer.update(email: nil)
      end

      it "returns a mailer with nil values" do
        mailer = payment_receipt_mailer.with(payment_receipt:).created

        expect(mailer.to).to be_nil
      end
    end

    context "when customer email is an empty string" do
      before do
        payment_receipt.payment.payable.customer.update(email: "")
      end

      it "returns a mailer with nil values" do
        mailer = payment_receipt_mailer.with(payment_receipt:).created

        expect(mailer.to).to be_nil
      end
    end
  end
end
