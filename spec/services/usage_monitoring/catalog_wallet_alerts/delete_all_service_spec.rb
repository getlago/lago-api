# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::DeleteAllService do
  let_it_be(:organization) { create(:organization) }

  context "with contract wallets" do
    subject(:result) { described_class.call(catalog_wallets: CatalogWallet.where(id: [wallet.id, second_wallet.id])) }

    let(:wallet) { create(:catalog_wallet, organization:) }
    let(:second_wallet) { create(:catalog_wallet, organization:) }
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: wallet) }
    let(:second_alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: second_wallet) }
    let(:kept_alert) { create(:catalog_wallet_alert, organization:) }

    before do
      create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, code: "low", value: 2_000)
      create(:catalog_wallet_triggered_alert, organization:, alert:, kind: :seeded, current_value: 1_500, previous_value: 1_500, crossed_thresholds: [{code: "low", value: BigDecimal(2_000), recurring: false}])
      second_alert
      kept_alert
    end

    it "deletes the given wallets' alerts with their thresholds, and keeps their history and the other wallets' alerts" do
      expect(result).to be_success
      expect(UsageMonitoring::CatalogWalletAlert.where(id: [alert.id, second_alert.id])).to be_empty
      expect(UsageMonitoring::CatalogWalletAlertThreshold.where(catalog_wallet_alert_id: alert.id)).to be_empty
      expect(UsageMonitoring::CatalogWalletTriggeredAlert.where(catalog_wallet_alert_id: alert.id).count).to eq(1)
      expect(UsageMonitoring::CatalogWalletAlert.where(id: kept_alert.id)).to exist
    end

    context "with one wallet" do
      subject(:result) { described_class.call(catalog_wallets: wallet) }

      it "deletes its alerts only" do
        expect(result).to be_success
        expect(UsageMonitoring::CatalogWalletAlert.where(id: alert.id)).to be_empty
        expect(UsageMonitoring::CatalogWalletAlert.where(id: [second_alert.id, kept_alert.id]).count).to eq(2)
      end
    end

    context "with no wallet" do
      subject(:result) { described_class.call(catalog_wallets: CatalogWallet.none) }

      it "deletes nothing" do
        expect { result }.not_to change(UsageMonitoring::CatalogWalletAlert, :count)
        expect(result).to be_success
      end
    end
  end

  context "with plan wallets" do
    subject(:result) { described_class.call(plan_wallets: plan_wallet) }

    let(:plan_wallet) { create(:plan_wallet, organization:) }
    let(:template) { create(:plan_wallet_alert, organization:, plan_wallet:) }
    let(:kept_template) { create(:plan_wallet_alert, organization:, plan_wallet: create(:plan_wallet, organization:)) }

    before do
      create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: template, code: "low", value: 2_000)
      kept_template
    end

    it "deletes the wallet's templates with their thresholds and keeps the other wallets' templates" do
      expect(result).to be_success
      expect(UsageMonitoring::PlanWalletAlert.where(id: template.id)).to be_empty
      expect(UsageMonitoring::CatalogWalletAlertThreshold.where(plan_wallet_alert_id: template.id)).to be_empty
      expect(UsageMonitoring::PlanWalletAlert.where(id: kept_template.id)).to exist
    end
  end
end
