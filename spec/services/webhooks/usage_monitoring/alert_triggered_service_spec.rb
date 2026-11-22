# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::UsageMonitoring::AlertTriggeredService do
  subject(:webhook_service) { described_class.new(object: triggered_alert) }

  let(:triggered_alert) { create(:triggered_alert) }

  describe ".call" do
    it_behaves_like "creates webhook", "alert.triggered", "triggered_alert"

    context "with a catalog wallet alert's history row" do
      let(:triggered_alert) { create(:catalog_wallet_triggered_alert) }

      it "renders it with the catalog wallet serializer" do
        webhook_service.call

        payload = Webhook.order(created_at: :desc).first.payload
        expected = V1::UsageMonitoring::CatalogWalletTriggeredAlertSerializer.new(triggered_alert, root_name: "triggered_alert").serialize
        expect(payload["triggered_alert"]).to eq(JSON.parse(expected.to_json))
        expect(payload["triggered_alert"]).to include("wallet_code" => triggered_alert.catalog_wallet.code)
      end
    end

    context "when SIDEKIQ_WEBHOOK is true" do
      before { ENV["SIDEKIQ_WEBHOOK"] = "true" }
      after { ENV.delete("SIDEKIQ_WEBHOOK") }

      it "enqueues the http job on the high priority queue" do
        webhook_service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.on_queue("webhook_worker_high_priority")
      end
    end
  end
end
