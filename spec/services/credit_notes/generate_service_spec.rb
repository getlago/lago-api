# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::GenerateService do
  subject(:credit_note_generate_service) { described_class.new(credit_note:, context:) }

  let(:organization) { create(:organization, name: "LAGO") }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:credit_note) { create(:credit_note, invoice:, customer:) }
  let(:fee) { create(:fee, invoice:) }
  let(:credit_note_item) { create(:credit_note_item, credit_note:, fee:) }
  let(:context) { nil }

  before do
    credit_note_item

    stub_pdf_generation
    allow(Utils::PdfGenerator).to receive(:call).and_call_original
  end

  describe ".call" do
    it "generates the credit note synchronously" do
      result = credit_note_generate_service.call

      expect(result.credit_note.file).to be_present
    end

    it "uses credit_note template" do
      credit_note_generate_service.call

      expect(Utils::PdfGenerator).to have_received(:call).with(template: "credit_notes/credit_note", context: credit_note)
    end

    it "produces an activity log" do
      result = credit_note_generate_service.call

      expect(Utils::ActivityLog).to have_produced("credit_note.generated").with(result.credit_note)
    end

    context "when credit note is for self billed invoice" do
      let(:invoice) { create(:invoice, :self_billed, customer:, organization:) }
      let(:credit_note) { create(:credit_note, invoice:, customer:) }

      it "uses self billed template" do
        credit_note_generate_service.call

        expect(Utils::PdfGenerator).to have_received(:call).with(template: "credit_notes/self_billed", context: credit_note)
      end
    end

    context "with preferred locale" do
      before { customer.update!(document_locale: "fr") }

      it "sets the correct document locale" do
        expect { credit_note_generate_service.call }
          .to change(I18n, :locale).from(:en).to(:fr)
      end
    end

    context "with not found credit_note" do
      let(:credit_note) { nil }
      let(:credit_note_item) { nil }

      it "returns a result with error" do
        result = credit_note_generate_service.call

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq("credit_note_not_found")
      end
    end

    context "when credit_note is draft" do
      let(:credit_note) { create(:credit_note, :draft, invoice:, customer:) }

      it "returns a not found error" do
        result = credit_note_generate_service.call

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq("credit_note_not_found")
      end
    end

    context "with already generated file" do
      before do
        credit_note.file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
          filename: "credit_note.pdf",
          content_type: "application/pdf"
        )
      end

      it "does not generate the pdf" do
        allow(LagoHttpClient::Client).to receive(:new)

        credit_note_generate_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context "when context is API" do
      let(:context) { "api" }

      it "calls the SendWebhook job" do
        expect do
          credit_note_generate_service.call
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when context is admin" do
      let(:context) { "admin" }

      it "calls the SendWebhook job" do
        expect do
          credit_note_generate_service.call
        end.to have_enqueued_job(SendWebhookJob)
      end
    end
  end
end
