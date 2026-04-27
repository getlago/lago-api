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

    context "when pdfs are disabled" do
      before { ENV["LAGO_DISABLE_PDF_GENERATION"] = "true" }

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
          payment_receipt_mailer.with(payment_receipt:).created
        }.to raise_error(PaymentReceipts::FilesNotReadyError, /payment_receipt .* file missing/)

        expect(PaymentReceipts::GeneratePdfService).to have_received(:new)
      end
    end

    context "when an invoice file is missing" do
      before { invoice.file.purge }

      it "raises FilesNotReadyError" do
        expect {
          payment_receipt_mailer.with(payment_receipt:).created
        }.to raise_error(PaymentReceipts::FilesNotReadyError, /invoice files missing/)
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
