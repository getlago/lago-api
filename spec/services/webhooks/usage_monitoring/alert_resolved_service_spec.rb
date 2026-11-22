# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::UsageMonitoring::AlertResolvedService do
  subject(:webhook_service) { described_class.new(object: resolved_alert) }

  let(:resolved_alert) do
    create(:triggered_alert, kind: :resolved, in_alarm_thresholds: ["warn"], fully_resolved: false)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "alert.resolved", "resolved_alert"

    context "with a catalog wallet alert's history row" do
      let(:resolved_alert) do
        create(:catalog_wallet_triggered_alert, kind: :resolved, resolution_reason: :threshold_removed, in_alarm_thresholds: [], fully_resolved: true)
      end

      it "renders it with the catalog wallet serializer" do
        webhook_service.call

        payload = Webhook.order(created_at: :desc).first.payload
        expected = V1::UsageMonitoring::CatalogWalletResolvedAlertSerializer.new(resolved_alert, root_name: "resolved_alert").serialize
        expect(payload["resolved_alert"]).to eq(JSON.parse(expected.to_json))
        expect(payload["resolved_alert"]).to include("wallet_code" => resolved_alert.catalog_wallet.code, "reason" => "threshold_removed")
      end
    end
  end
end
