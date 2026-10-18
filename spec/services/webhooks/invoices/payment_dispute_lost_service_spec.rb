# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::PaymentDisputeLostService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, :dispute_lost, customer:, organization:) }

  before do
    create_list(:fee, 2, invoice:)
    create_list(:credit, 2, invoice:)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.payment_dispute_lost", "payment_dispute_lost", {"invoice" => Hash}

    it "keeps the v1 invoice for a legacy invoice" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload["payment_dispute_lost"]["invoice"]
      expect(payload).to include("lago_id" => invoice.id)
      expect(payload).to have_key("self_billed")
      expect(payload).not_to have_key("contracts")
    end

    context "with a catalog invoice" do
      subject(:webhook_service) { described_class.new(object: catalog_invoice, options: {provider_error: {"message" => "declined"}}) }

      let(:catalog_invoice) { create(:invoice, :dispute_lost, organization:, customer:, invoice_type: :contract) }

      it "sends the v2 invoice with the provider error" do
        webhook_service.call

        payload = Webhook.order(created_at: :desc).first.payload["payment_dispute_lost"]
        expect(payload["invoice"]).to include("lago_id" => catalog_invoice.id, "invoice_type" => "contract", "contracts" => [], "fees" => [])
        expect(payload["invoice"]).not_to have_key("subscriptions")
        expect(payload["invoice"]).not_to have_key("self_billed")
        expect(payload["provider_error"]).to eq("message" => "declined")
      end
    end
  end
end
