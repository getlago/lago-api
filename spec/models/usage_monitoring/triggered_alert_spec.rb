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
      expect(subject).to define_enum_for(:resolution_reason)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(recovered: "recovered", threshold_updated: "threshold_updated", threshold_removed: "threshold_removed")
        .with_prefix
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

  describe "#alertable=" do
    subject(:triggered_alert) { described_class.new }

    let(:subscription) { create(:subscription) }
    let(:wallet) { create(:wallet) }

    it "assigns a subscription" do
      triggered_alert.alertable = subscription
      expect(triggered_alert).to have_attributes(subscription:, wallet: nil)
    end

    it "assigns a wallet" do
      triggered_alert.alertable = wallet
      expect(triggered_alert).to have_attributes(wallet:, subscription: nil)
    end

    it "rejects anything else" do
      expect { triggered_alert.alertable = Customer.new }.to raise_error(ArgumentError, "unsupported alertable: Customer")
    end
  end
end
