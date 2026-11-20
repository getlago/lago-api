# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::UpdateService do
  subject(:result) { described_class.call(alert:, params:) }

  let_it_be(:organization) { create(:organization) }

  let(:alert) { create(:plan_wallet_alert, organization:, alert_type: "balance", code: "low_balance", name: "Low balance") }
  let(:params) { {name: "Running low", thresholds: [{code: "low", value: "5000"}, {value: "0"}]} }

  before do
    create(:catalog_wallet_alert_threshold, :template, plan_wallet_alert: alert, organization:, code: "low", value: 10_000, notify_on: %w[triggered resolved])
  end

  it "updates the name and replaces the thresholds, keeping the notify_on of a threshold by its code" do
    expect(result).to be_success
    expect(result.alert).to eq(alert)
    expect(alert.reload.name).to eq("Running low")
    expect(alert.thresholds.order(:value).pluck(:code, :value, :notify_on)).to eq([
      [nil, 0, %w[triggered]],
      ["low", 5000, %w[triggered resolved]]
    ])
  end

  context "with only a name" do
    let(:params) { {name: "Running low"} }

    it "keeps the thresholds" do
      expect(result).to be_success
      expect(alert.reload.thresholds.pluck(:code, :value)).to eq([["low", 10_000]])
    end
  end

  context "with only thresholds" do
    let(:params) { {thresholds: [{value: "100"}]} }

    it "keeps the name and dates the template" do
      travel_to(1.day.from_now) do
        expect(result).to be_success
        expect(alert.reload).to have_attributes(name: "Low balance", updated_at: Time.current)
        expect(alert.thresholds.pluck(:value)).to eq([100])
      end
    end
  end

  context "with the code or the alert type" do
    let(:params) { {code: "other", alert_type: "ongoing_balance"} }

    it "refuses both" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({code: ["value_cannot_be_changed"], alert_type: ["value_cannot_be_changed"]})
    end
  end

  context "with a fraction of a cent" do
    let(:params) { {thresholds: [{value: "100.5"}]} }

    it "fails and keeps the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      expect(alert.reload.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "with an empty list of thresholds" do
    let(:params) { {thresholds: []} }

    it "fails and keeps the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
      expect(alert.reload.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "with a negative threshold on a balance alert" do
    let(:params) { {thresholds: [{value: "-100"}]} }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
    end
  end

  context "with a recurring step on its own on a balance alert" do
    # Its first line sits one step below 0, which a balance never reaches
    let(:params) { {thresholds: [{value: "5000", recurring: true}]} }

    it "fails and keeps the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      expect(alert.reload.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "when a threshold cannot be saved" do
    # The controller keeps only the threshold fields, so only a direct caller can send this one
    let(:params) { {name: "Running low", thresholds: [{value: "100", organization_id: nil}]} }

    it "fails and keeps the name and the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({organization: ["relation_must_exist"]})
      expect(alert.reload.name).to eq("Low balance")
      expect(alert.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "with a negative threshold on an ongoing balance alert" do
    let(:alert) { create(:plan_wallet_alert, organization:, alert_type: "ongoing_balance", code: "low_balance", name: "Low balance") }
    let(:params) { {thresholds: [{value: "-100"}]} }

    it "accepts it, since unbilled usage can take the ongoing balance below 0" do
      expect(result).to be_success
      expect(alert.reload.thresholds.pluck(:value)).to eq([-100])
    end
  end

  context "without an alert" do
    subject(:result) { described_class.call(alert: nil, params:) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end

  context "when another request renamed the template after this one loaded it" do
    let(:params) { {name: "Low balance"} }

    before { UsageMonitoring::PlanWalletAlert.find(alert.id).update!(name: "Renamed elsewhere") }

    it "saves the name it was asked for" do
      expect(result).to be_success
      expect(alert.reload.name).to eq("Low balance")
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
    before { PlanWallet.find(alert.plan_wallet_id).discard! }

    it "fails and keeps the template as it was" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("plan_wallet_not_found")
      expect(alert.reload.name).to eq("Low balance")
    end
  end
end
