# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractTriggeredAlert do
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
      expect(subject).to belong_to(:contract)
      expect(subject).to belong_to(:alert).class_name("UsageMonitoring::ContractAlert")
        .with_foreign_key(:contract_alert_id)
    end

    it "resolves a discarded alert" do
      triggered_alert = create(:contract_triggered_alert)
      triggered_alert.alert.discard!

      expect(described_class.find(triggered_alert.id).alert).to eq(triggered_alert.alert)
    end
  end

  describe "kind" do
    it "records a trigger by default" do
      expect(create(:contract_triggered_alert)).to be_triggered
    end
  end

  describe "#alertable=" do
    subject(:triggered_alert) { described_class.new }

    it "assigns a contract" do
      contract = create(:contract)
      triggered_alert.alertable = contract

      expect(triggered_alert.contract).to eq(contract)
    end

    it "rejects anything else" do
      expect { triggered_alert.alertable = Subscription.new }
        .to raise_error(ArgumentError, "unsupported alertable: Subscription")
    end
  end
end
