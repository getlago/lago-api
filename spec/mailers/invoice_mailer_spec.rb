# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceMailer, type: :mailer do
  subject(:invoice_mailer) { described_class }

  let(:invoice) { create(:invoice, fees_amount_cents: 100) }

  before do
    invoice.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "blank.pdf")
  end

  describe "#finalized" do
    specify do
      mailer = invoice_mailer.with(invoice:).finalized

      expect(mailer.to).to eq([invoice.customer.email])
      expect(mailer.reply_to).to eq([invoice.organization.email])
      expect(mailer.attachments).not_to be_empty
    end

    context "with no pdf file" do
      let(:pdf_service) { instance_double(Invoices::GeneratePdfService) }

      before do
        invoice.file = nil

        allow(Invoices::GeneratePdfService).to receive(:new)
          .and_return(pdf_service)
        allow(pdf_service).to receive(:call)
      end

      it "calls the invoice pdf generate service" do
        mailer = invoice_mailer.with(invoice:).finalized

        expect(mailer.to).not_to be_nil
        expect(Invoices::GeneratePdfService).to have_received(:new)
      end
    end

    context "when organization email is nil" do
      before do
        invoice.organization.update(email: nil)
      end

      it "returns a mailer with nil values" do
        mailer = invoice_mailer.with(invoice:).finalized

        expect(mailer.to).to be_nil
      end
    end

    context "when customer email is nil" do
      before do
        invoice.customer.update(email: nil)
      end

      it "returns a mailer with nil values" do
        mailer = invoice_mailer.with(invoice:).finalized

        expect(mailer.to).to be_nil
      end
    end

    context "when invoice fees amount is zero" do
      before do
        invoice.update(fees_amount_cents: 0)
      end

      it "returns a mailer with nil values" do
        mailer = invoice_mailer.with(invoice:).finalized

        expect(mailer.to).to be_nil
      end
    end
  end
end
