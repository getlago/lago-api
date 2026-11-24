# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlertThreshold do
  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:alert).class_name("UsageMonitoring::ContractAlert")
        .with_foreign_key(:contract_alert_id)
    end
  end

  describe "notify_on" do
    it "notifies on trigger only by default" do
      expect(create(:contract_alert_threshold).notify_on).to eq(["triggered"])
    end

    it "drops duplicates and keeps one order" do
      threshold = create(:contract_alert_threshold, notify_on: %w[resolved triggered resolved])

      expect(threshold.notify_on).to eq(%w[triggered resolved])
    end
  end

  describe "#notify_on_resolved?" do
    it "is false when the threshold notifies on trigger only" do
      expect(create(:contract_alert_threshold)).not_to be_notify_on_resolved
    end

    it "is true when the threshold opted in to resolution" do
      expect(create(:contract_alert_threshold, notify_on: %w[triggered resolved])).to be_notify_on_resolved
    end
  end
end
