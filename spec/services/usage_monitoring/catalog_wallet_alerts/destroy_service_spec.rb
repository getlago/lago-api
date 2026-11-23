# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::DestroyService do
  subject(:result) { described_class.call(alert:) }

  let_it_be(:organization) { create(:organization) }

  let(:alert) { create(:plan_wallet_alert, organization:) }

  before { create(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: alert, organization:) }

  it "deletes the template and its thresholds for good" do
    expect(result).to be_success
    expect(result.alert).to eq(alert)
    expect(UsageMonitoring::PlanWalletAlert.where(id: alert.id)).to be_empty
    expect(UsageMonitoring::CatalogWalletAlertThreshold.where(plan_wallet_alert_id: alert.id)).to be_empty
  end

  context "when the wallet has another template" do
    let(:other_alert) { create(:plan_wallet_alert, organization:, plan_wallet: alert.plan_wallet, alert_type: "ongoing_balance") }

    before { create(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: other_alert, organization:) }

    it "keeps it with its thresholds" do
      expect(result).to be_success
      expect(other_alert.reload.thresholds.count).to eq(1)
    end
  end

  context "without an alert" do
    subject(:result) { described_class.call(alert: nil) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end

  context "when the alert was deleted before the lock" do
    before { UsageMonitoring::PlanWalletAlert.find(alert.id).destroy! }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end

  context "when the plan wallet was deleted before the lock" do
    before { PlanWallets::DestroyService.call!(plan_wallet: PlanWallet.find(alert.plan_wallet_id)) }

    it "fails on the plan wallet, as the update does" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("plan_wallet_not_found")
    end
  end

  context "when another request renamed the template after this one loaded it" do
    before { UsageMonitoring::PlanWalletAlert.find(alert.id).update!(name: "Renamed elsewhere") }

    it "renders the template as it was deleted" do
      expect(result).to be_success
      expect(result.alert.name).to eq("Renamed elsewhere")
    end
  end
end
