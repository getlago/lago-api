# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletTriggeredAlert do
  subject(:triggered_alert) { build(:catalog_wallet_triggered_alert) }

  describe "enums" do
    it do
      expect(triggered_alert).to define_enum_for(:kind)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(triggered: "triggered", resolved: "resolved", seeded: "seeded")
      expect(triggered_alert).to define_enum_for(:resolution_reason)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(recovered: "recovered", threshold_updated: "threshold_updated", threshold_removed: "threshold_removed")
        .with_prefix
      expect(triggered_alert).to define_enum_for(:alert_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(balance: "balance", ongoing_balance: "ongoing_balance")
    end
  end

  describe "associations" do
    it do
      expect(triggered_alert).to belong_to(:organization)
      expect(triggered_alert).to belong_to(:catalog_wallet)
      expect(triggered_alert).to belong_to(:alert).class_name("UsageMonitoring::CatalogWalletAlert")
        .with_foreign_key(:catalog_wallet_alert_id).optional.inverse_of(:all_triggered_alerts)
    end
  end

  describe "soft deleted associations" do
    let(:catalog_wallet) { create(:catalog_wallet, deleted_at: Time.current) }
    let(:alert) { create(:catalog_wallet_alert, catalog_wallet:, organization: catalog_wallet.organization) }
    let(:history) { create(:catalog_wallet_triggered_alert, alert:) }

    it "still resolves a discarded wallet" do
      expect(described_class.find(history.id).catalog_wallet).to eq(catalog_wallet)
    end
  end

  describe "a copy of the alert" do
    let(:alert) { create(:catalog_wallet_alert, code: "low_balance", name: "Low balance", alert_type: "ongoing_balance") }
    let(:history) { alert.all_triggered_alerts.create!(organization: alert.organization, alertable: alert.catalog_wallet, current_value: 1000, previous_value: 3000, crossed_thresholds: [], triggered_at: Time.current) }

    it "keeps the alert's code, name and type, written as the shared engine writes history" do
      expect(history).to have_attributes(alert_code: "low_balance", alert_name: "Low balance", alert_type: "ongoing_balance", kind: "triggered")
    end

    it "stays with the alert id when the alerts are deleted in bulk, as when the contract ends" do
      create(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert)
      history

      UsageMonitoring::CatalogWalletAlert.where(id: alert.id).delete_all

      expect(UsageMonitoring::CatalogWalletAlertThreshold.where(catalog_wallet_alert_id: alert.id)).to be_empty
      expect(history.reload).to have_attributes(alert: nil, catalog_wallet_alert_id: alert.id, alert_code: "low_balance", alert_name: "Low balance", alert_type: "ongoing_balance")
    end
  end

  describe "#alertable=" do
    subject(:triggered_alert) { described_class.new }

    it "assigns a catalog wallet" do
      catalog_wallet = build(:catalog_wallet)
      triggered_alert.alertable = catalog_wallet

      expect(triggered_alert.catalog_wallet).to eq(catalog_wallet)
    end

    it "rejects anything else" do
      expect { triggered_alert.alertable = Wallet.new }
        .to raise_error(ArgumentError, "unsupported alertable: Wallet")
    end
  end
end
