# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::DestroyAllAlertsService do
  describe ".call" do
    subject(:result) { described_class.call(organization:, subscription:) }

    let(:organization) { create(:organization) }
    let(:subscription) { create(:subscription, organization:) }

    let(:alert1) do
      create(:usage_current_amount_alert, code: "a1", organization:,
        subscription_external_id: subscription.external_id, thresholds: [1, 2])
    end
    let(:alert2) do
      create(:lifetime_usage_amount_alert, code: "a2", organization:,
        subscription_external_id: subscription.external_id, thresholds: [3])
    end
    let(:other_alert) { create(:alert, organization:, thresholds: [4]) }

    before do
      alert1
      alert2
      other_alert
    end

    it "discards all alerts for the subscription" do
      expect(result).to be_success
      expect(result.alerts.count).to eq 2

      expect(alert1.reload).to be_discarded
      expect(alert2.reload).to be_discarded
      expect(other_alert.reload).not_to be_discarded
    end

    it "deletes all thresholds for the discarded alerts" do
      expect { result }.to change(UsageMonitoring::AlertThreshold, :count).by(-3)
    end

    context "when there are no alerts for the subscription" do
      let(:alert1) { nil }
      let(:alert2) { nil }

      it "returns success with empty alerts" do
        expect(result).to be_success
        expect(result.alerts).to be_empty
      end
    end
  end
end
