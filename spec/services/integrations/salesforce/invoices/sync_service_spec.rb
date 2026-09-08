# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Salesforce::Invoices::SyncService do
  subject(:sync_service) { described_class.new(invoice) }

  describe "#call" do
    context "when invoice is nil" do
      let(:invoice) { nil }

      it "returns a not found failure" do
        result = sync_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("invoice")
      end

      it "does not enqueue a webhook job" do
        expect { sync_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when invoice is present" do
      let(:invoice) { create(:invoice) }

      it "enqueues an invoice.resynced webhook job" do
        expect { sync_service.call }
          .to have_enqueued_job(SendWebhookJob)
          .with("invoice.resynced", invoice)
      end

      it "returns the invoice id in the result" do
        result = sync_service.call

        expect(result).to be_success
        expect(result.invoice_id).to eq(invoice.id)
      end
    end
  end
end
