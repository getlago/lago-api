# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::AlertThreshold do
  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:alert).class_name("UsageMonitoring::Alert")
        .with_foreign_key(:usage_monitoring_alert_id)
    end
  end

  describe "notify_on" do
    it "notifies on trigger only by default" do
      expect(create(:alert_threshold).notify_on).to eq(["triggered"])
    end
  end

  describe "#notify_on_resolved?" do
    it "is false when the threshold notifies on trigger only" do
      expect(create(:alert_threshold)).not_to be_notify_on_resolved
    end

    it "is true when the threshold opted in to resolution" do
      expect(create(:alert_threshold, notify_on: %w[triggered resolved])).to be_notify_on_resolved
    end
  end
end
