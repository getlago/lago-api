# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNoteMailer, type: :mailer do
  subject(:credit_note_mailer) { described_class }

  let(:credit_note) { create(:credit_note) }

  around { |test| lago_premium!(&test) }

  before do
    credit_note.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "blank.pdf")
  end

  describe "#created" do
    specify do
      mailer = credit_note_mailer.with(credit_note:).created

      expect(mailer.to).to eq([credit_note.customer.email])
      expect(mailer.reply_to).to eq([credit_note.organization.email])
      expect(mailer.attachments).not_to be_empty
      expect(mailer.attachments.first.filename).to eq("credit_note-#{credit_note.number}.pdf")
    end

    context "with no pdf file" do
      let(:pdf_service) { instance_double(CreditNotes::GenerateService) }

      before do
        credit_note.file = nil

        allow(CreditNotes::GenerateService).to receive(:new)
          .and_return(pdf_service)
        allow(pdf_service).to receive(:call)
      end

      it "calls the credit note pdf generate service" do
        mailer = credit_note_mailer.with(credit_note:).created

        expect(mailer.to).not_to be_nil
        expect(CreditNotes::GenerateService).to have_received(:new)
      end
    end

    context "when organization email is nil" do
      before do
        credit_note.organization.update(email: nil)
      end

      it "returns a mailer with nil values" do
        mailer = credit_note_mailer.with(credit_note:).created

        expect(mailer.to).to be_nil
      end
    end

    context "when customer email is nil" do
      before do
        credit_note.customer.update(email: nil)
      end

      it "returns a mailer with nil values" do
        mailer = credit_note_mailer.with(credit_note:).created

        expect(mailer.to).to be_nil
      end
    end

    context "when organization from_email integration is enabled" do
      before do
        credit_note.organization.update(premium_integrations: ["from_email"])
      end

      it "returns a mailer with organization email from" do
        mailer = credit_note_mailer.with(credit_note:).created

        expect(mailer.from).to eq([credit_note.customer.organization.email])
      end
    end
  end
end
