# frozen_string_literal: true

RSpec.shared_examples "sends the catalog invoice on v2" do
  it "keeps the v1 payload for a legacy invoice" do
    webhook_service.call

    payload = Webhook.order(created_at: :desc).first.payload["invoice"]
    expect(payload).to include("lago_id" => invoice.id)
    expect(payload).to have_key("self_billed")
    expect(payload).not_to have_key("contracts")
  end

  context "with a catalog invoice" do
    let(:catalog_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }

    it "sends the v2 payload" do
      described_class.new(object: catalog_invoice).call

      payload = Webhook.order(created_at: :desc).first.payload["invoice"]
      expect(payload).to include("lago_id" => catalog_invoice.id, "invoice_type" => "contract", "contracts" => [], "fees" => [])
      expect(payload).not_to have_key("subscriptions")
      expect(payload).not_to have_key("self_billed")
    end
  end
end
