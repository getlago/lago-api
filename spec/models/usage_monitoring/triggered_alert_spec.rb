# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::TriggeredAlert do
  let(:triggered_alert) { create(:triggered_alert) }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:kind)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(triggered: "triggered", resolved: "resolved", seeded: "seeded")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription).optional
      expect(subject).to belong_to(:wallet).optional
      expect(subject).to belong_to(:alert).class_name("UsageMonitoring::Alert")
        .with_foreign_key(:usage_monitoring_alert_id)
    end
  end

  describe "kind" do
    it "records a trigger by default" do
      expect(triggered_alert).to be_triggered
    end
  end

  describe "resolution columns" do
    it "records which codes remain in alarm and whether the alert is fully resolved" do
      resolved = create(:triggered_alert, kind: :resolved, in_alarm_thresholds: ["warn"], fully_resolved: false)

      expect(resolved.reload).to have_attributes(in_alarm_thresholds: ["warn"], fully_resolved: false)
    end
  end
end
