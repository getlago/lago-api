# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlertThreshold do
  subject(:threshold) { build(:catalog_wallet_alert_threshold) }

  describe "associations" do
    it do
      expect(threshold).to belong_to(:organization)
      expect(threshold).to belong_to(:plan_wallet_alert).class_name("UsageMonitoring::PlanWalletAlert").optional.inverse_of(:thresholds)
      expect(threshold).to belong_to(:catalog_wallet_alert).class_name("UsageMonitoring::CatalogWalletAlert").optional.inverse_of(:thresholds)
    end
  end

  describe "validations" do
    it "accepts a contract wallet alert or a template as owner" do
      expect(build(:catalog_wallet_alert_threshold)).to be_valid
      expect(build(:catalog_wallet_alert_threshold, :template)).to be_valid
    end

    it "rejects a threshold with no owner or two owners" do
      orphan = build(:catalog_wallet_alert_threshold, catalog_wallet_alert: nil, organization: create(:organization))
      both = build(:catalog_wallet_alert_threshold, plan_wallet_alert: create(:plan_wallet_alert))

      expect(orphan.tap(&:valid?).errors).to be_added(:base, :exactly_one_owner_required)
      expect(both.tap(&:valid?).errors).to be_added(:base, :exactly_one_owner_required)
    end
  end

  describe "notify_on" do
    it "notifies on trigger only by default" do
      expect(create(:catalog_wallet_alert_threshold).notify_on).to eq(["triggered"])
    end

    it "drops duplicates and keeps one order" do
      threshold = create(:catalog_wallet_alert_threshold, notify_on: %w[resolved triggered resolved])

      expect(threshold.notify_on).to eq(%w[triggered resolved])
    end
  end

  describe "#notify_on_resolved?" do
    it "is false when the threshold notifies on trigger only" do
      expect(create(:catalog_wallet_alert_threshold)).not_to be_notify_on_resolved
    end

    it "is true when the threshold opted in to resolution" do
      expect(create(:catalog_wallet_alert_threshold, notify_on: %w[triggered resolved])).to be_notify_on_resolved
    end
  end

  describe "database constraints" do
    let(:alert) { create(:catalog_wallet_alert) }

    it "refuses a threshold without an owner" do
      orphan = build(:catalog_wallet_alert_threshold, catalog_wallet_alert: nil, organization: alert.organization)

      expect { orphan.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_alert_thresholds_one_owner/)
    end

    it "refuses a threshold with two owners" do
      both = build(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert, plan_wallet_alert: create(:plan_wallet_alert))

      expect { both.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_alert_thresholds_one_owner/)
    end

    it "accepts a plain threshold at zero and several plain thresholds on one alert" do
      create(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert, value: 0)

      expect { create(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert, value: 500) }
        .to change(described_class, :count).by(1)
    end

    it "refuses a recurring step of zero" do
      zero_step = build(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert, recurring: true, value: 0)

      expect { zero_step.save! }.to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_alert_thresholds_recurring_step_positive/)
    end

    it "refuses a second recurring threshold on a contract wallet alert" do
      create(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert, recurring: true, value: 1000)
      second = build(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert, recurring: true, value: 500)

      expect { second.save! }.to raise_error(ActiveRecord::RecordNotUnique, /idx_catalog_wallet_alert_thresholds_catalog_recurring_unique/)
    end

    it "refuses a second recurring threshold on a template" do
      template = create(:plan_wallet_alert)
      create(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: template, recurring: true, value: 1000)
      second = build(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: template, recurring: true, value: 500)

      expect { second.save! }.to raise_error(ActiveRecord::RecordNotUnique, /idx_catalog_wallet_alert_thresholds_plan_recurring_unique/)
    end

    it "deletes the thresholds of a deleted alert" do
      create(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert)

      expect { alert.delete }.to change(described_class, :count).by(-1)
    end

    it "deletes the thresholds of a deleted template" do
      template = create(:plan_wallet_alert)
      create(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: template)

      expect { template.delete }.to change(described_class, :count).by(-1)
    end

    it "deletes the thresholds of an alert through the association, as the shared engine replaces them" do
      create(:catalog_wallet_alert_threshold, catalog_wallet_alert: alert)

      expect { alert.thresholds.delete_all }.to change(described_class, :count).by(-1)
    end

    it "deletes the thresholds of a template through the association" do
      template = create(:plan_wallet_alert)
      create(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: template)

      expect { template.thresholds.delete_all }.to change(described_class, :count).by(-1)
    end
  end
end
