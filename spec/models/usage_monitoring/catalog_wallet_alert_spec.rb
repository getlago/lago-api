# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlert do
  subject(:alert) { build(:catalog_wallet_alert) }

  it_behaves_like "a catalog code", :catalog_wallet_alert

  describe "enums" do
    it do
      expect(alert).to define_enum_for(:alert_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(balance: "balance", ongoing_balance: "ongoing_balance")
    end
  end

  describe "associations" do
    it do
      expect(alert).to belong_to(:organization)
      expect(alert).to belong_to(:catalog_wallet).inverse_of(:alerts)
      expect(alert).to have_many(:thresholds).class_name("UsageMonitoring::CatalogWalletAlertThreshold").dependent(:delete_all).inverse_of(:catalog_wallet_alert)
      expect(alert).to have_many(:all_triggered_alerts).class_name("UsageMonitoring::CatalogWalletTriggeredAlert").inverse_of(:alert)
    end
  end

  describe "soft deleted associations" do
    let(:catalog_wallet) { create(:catalog_wallet, deleted_at: Time.current) }
    let(:wallet_alert) { create(:catalog_wallet_alert, catalog_wallet:, organization: catalog_wallet.organization) }

    it "still resolves a discarded wallet" do
      expect(described_class.find(wallet_alert.id).catalog_wallet).to eq(catalog_wallet)
    end
  end

  describe "validations" do
    it { expect(alert).to validate_presence_of(:code) }
  end

  describe "#discarded?" do
    it "is false, since a deleted alert cannot be loaded" do
      expect(alert.discarded?).to be(false)
    end
  end

  describe "direction" do
    it "watches a balance going down" do
      expect(alert).to be_decreasing
      expect(alert).not_to be_increasing
    end
  end

  describe "database constraints" do
    let(:existing) { create(:catalog_wallet_alert, alert_type: "balance", code: "low") }

    it "refuses a second alert of the same type on the wallet" do
      duplicate = build(:catalog_wallet_alert, catalog_wallet: existing.catalog_wallet, organization: existing.organization, alert_type: "balance", code: "other")

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique, /idx_catalog_wallet_alerts_alert_type_unique/)
    end

    it "refuses a second alert with the same code on the wallet" do
      duplicate = build(:catalog_wallet_alert, catalog_wallet: existing.catalog_wallet, organization: existing.organization, alert_type: "ongoing_balance", code: "low")

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique, /idx_catalog_wallet_alerts_code_unique/)
    end

    it "accepts the same type and code on another wallet" do
      other = build(:catalog_wallet_alert, organization: existing.organization, alert_type: "balance", code: "low")

      expect { other.save! }.not_to raise_error
    end

    context "when the alert holding them is deleted" do
      before { existing.destroy! }

      it "accepts the same type and code on the wallet again" do
        recreated = build(:catalog_wallet_alert, catalog_wallet: existing.catalog_wallet, organization: existing.organization, alert_type: "balance", code: "low")

        expect { recreated.save! }.not_to raise_error
      end
    end
  end
end
