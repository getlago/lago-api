# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipts::GeneratePdfService, type: :service do
  subject(:payment_receipt_generate_service) { described_class.new(payment_receipt:, context:) }

  let(:context) { "graphql" }
  let(:organization) { create(:organization, name: "LAGO") }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:invoice) { create(:invoice, customer:, status: :finalized, organization:) }
  let(:payment) { create(:payment, payable: invoice) }
  let(:payment_receipt) { create(:payment_receipt, payment:, organization:) }

  before { stub_pdf_generation }

  describe "#call" do
    it "generates the payment receipt synchronously" do
      result = payment_receipt_generate_service.call

      expect(result.payment_receipt.file).to be_present
    end

    it "calls the SendWebhook job" do
      expect { payment_receipt_generate_service.call }.to have_enqueued_job(SendWebhookJob)
    end

    context "with not found payment receipt" do
      let(:payment_receipt) { nil }

      it "returns a result with error" do
        result = payment_receipt_generate_service.call

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq("payment_receipt_not_found")
      end
    end

    context "with already generated file" do
      before do
        payment_receipt.file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
          filename: "receipt.pdf",
          content_type: "application/pdf"
        )
      end

      it "does not generate the pdf" do
        allow(LagoHttpClient::Client).to receive(:new)

        payment_receipt_generate_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
      end

      it "does not call the SendWebhook job" do
        expect { payment_receipt_generate_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when in API context" do
      let(:context) { "api" }

      it "calls the SendWebhook job" do
        expect { payment_receipt_generate_service.call }.to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when in Admin context" do
      let(:context) { "admin" }

      before do
        invoice.file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
          filename: "receipt.pdf",
          content_type: "application/pdf"
        )
      end

      it "generates the invoice synchronously" do
        result = payment_receipt_generate_service.call

        expect(result.payment_receipt.file.filename.to_s).not_to eq("receipt.pdf")
      end
    end
  end
end
