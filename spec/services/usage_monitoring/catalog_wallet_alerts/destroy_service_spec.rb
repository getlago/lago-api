# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::DestroyService do
  subject(:result) { described_class.call(alert:) }

  let_it_be(:organization) { create(:organization) }

  let(:alert) { create(:plan_wallet_alert, organization:) }

  # Through the alert's own association, which holds a template's thresholds as well as a contract wallet alert's
  before { alert.thresholds.create!(organization:, value: 2000) }

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

  context "with an alert on a contract wallet" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, customer:) }
    let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:) }
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }
    let(:history) { create(:catalog_wallet_triggered_alert, organization:, alert:) }

    before { history }

    it "deletes the alert and its thresholds for good, keeps its history and sends nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)

      expect(result).to be_success
      expect(result.alert).to eq(alert)
      expect(UsageMonitoring::CatalogWalletAlert.where(id: alert.id)).to be_empty
      expect(UsageMonitoring::CatalogWalletAlertThreshold.where(catalog_wallet_alert_id: alert.id)).to be_empty
      expect(history.reload).to have_attributes(
        catalog_wallet_alert_id: alert.id,
        alert_code: "low_balance",
        alert_name: "Low balance",
        alert_type: "balance"
      )
    end

    context "when the wallet has ended" do
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, terminated_at: Time.current) }

      it "refuses the write and keeps the alert" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("wallet_alerts_read_only")
        expect(alert.reload.thresholds.count).to eq(1)
      end
    end

    context "when the contract was terminated after the alert was loaded" do
      before { Contracts::TerminateService.call!(contract: Contract.find(contract.id)) }

      it "refuses the write" do
        expect(result).to be_failure
        expect(result.error.code).to eq("contract_not_live")
      end
    end

    context "when the wallet was deleted before the lock" do
      before { CatalogWallet.find(catalog_wallet.id).discard! }

      it "fails and keeps the alert" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("contract_wallet_not_found")
        expect(alert.reload.thresholds.count).to eq(1)
      end
    end

    context "when the alert was deleted before the lock" do
      before { UsageMonitoring::CatalogWalletAlert.find(alert.id).destroy! }

      it "fails" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("alert_not_found")
      end
    end
  end
end
