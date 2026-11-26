# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::CopyTemplatesService do
  subject(:result) { described_class.call(plan_wallet: load_plan_wallet, catalog_wallet:) }

  let_it_be(:organization) { create(:organization) }

  let(:plan_wallet) { create(:plan_wallet, organization:) }
  let(:catalog_wallet) { create(:catalog_wallet, organization:) }

  let(:template) { create(:plan_wallet_alert, organization:, plan_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }
  let(:template_thresholds) do
    [
      create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: template, code: "warning", value: 10_000, notify_on: %w[triggered resolved]),
      create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: template, code: nil, value: 2_000, recurring: true)
    ]
  end

  before { template_thresholds }

  it "gives the wallet its own copy of the template, thresholds included" do
    expect(result).to be_success

    alert = catalog_wallet.alerts.sole
    expect(result.alerts).to eq([alert])
    expect(alert.id).not_to eq(template.id)
    expect(alert).to have_attributes(
      organization:,
      alert_type: "balance",
      code: "low_balance",
      name: "Low balance",
      previous_value: nil,
      last_processed_at: nil
    )
    expect(alert.thresholds.order(:value).map { [it.organization, it.code, it.value, it.recurring, it.notify_on, it.plan_wallet_alert_id] })
      .to eq([
        [organization, nil, 2_000, true, %w[triggered], nil],
        [organization, "warning", 10_000, false, %w[triggered resolved], nil]
      ])
  end

  it "records no history" do
    expect { result }.not_to change(UsageMonitoring::CatalogWalletTriggeredAlert, :count)
  end

  it "leaves the template untouched" do
    expect { result }.not_to change { template.reload.thresholds.order(:value).pluck(:id, :value, :catalog_wallet_alert_id) }
  end

  context "when the plan wallet has several templates" do
    # Created first, though it comes second by code and by alert type
    let(:ongoing_template) do
      create(:plan_wallet_alert, organization:, plan_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance", name: nil, created_at: 1.minute.ago)
    end

    before { create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: ongoing_template, code: "empty", value: 0) }

    it "copies each one with its own thresholds, in the templates' order" do
      expect(result.alerts.map(&:code)).to eq(%w[low_ongoing_balance low_balance])
      expect(catalog_wallet.alerts.order(:created_at).pluck(:code)).to eq(%w[low_ongoing_balance low_balance])

      alerts = catalog_wallet.alerts.index_by(&:alert_type)
      expect(alerts.fetch("balance").thresholds.pluck(:value)).to contain_exactly(2_000, 10_000)
      expect(alerts.fetch("ongoing_balance")).to have_attributes(code: "low_ongoing_balance", name: nil)
      expect(alerts.fetch("ongoing_balance").thresholds.pluck(:code, :value)).to eq([["empty", 0]])
    end

    # A frozen clock sits on a whole second, where a float offset of one microsecond rounds down to the same timestamp
    it "dates each copy apart on a frozen clock" do
      freeze_time { result }

      expect(catalog_wallet.alerts.distinct.count(:created_at)).to eq(2)
      expect(catalog_wallet.alerts.order(:created_at).pluck(:code)).to eq(%w[low_ongoing_balance low_balance])
    end

    # The copy runs under the customer's billing lock, so it holds it for one statement per table, not one per row
    it "inserts the alerts in one statement and their thresholds in another" do
      plan_wallet = load_plan_wallet
      wallet = catalog_wallet

      inserts = capture_sql { described_class.call!(plan_wallet:, catalog_wallet: wallet) }.grep(/\AINSERT/)

      expect(inserts.map { it[/\AINSERT INTO "(\w+)"/, 1] }).to eq(%w[usage_monitoring_catalog_wallet_alerts usage_monitoring_catalog_wallet_alert_thresholds])
    end
  end

  context "when another plan wallet has templates" do
    let(:template) { create(:plan_wallet_alert, organization:, plan_wallet: create(:plan_wallet, organization:)) }

    it "copies none of them" do
      expect { result }.not_to change(UsageMonitoring::CatalogWalletAlert, :count)
      expect(result.alerts).to be_empty
    end
  end

  context "when the plan wallet has no template" do
    let(:template_thresholds) { [] }

    it "gives the wallet no alert" do
      expect { result }.not_to change(UsageMonitoring::CatalogWalletAlert, :count)
      expect(result).to be_success
      expect(result.alerts).to be_empty
    end
  end

  context "when the wallet was inserted before" do
    let(:catalog_wallet) { CatalogWallet.find(create(:catalog_wallet, organization:).id) }

    it "copies nothing onto a wallet it did not just insert" do
      expect { result }.not_to change(UsageMonitoring::CatalogWalletAlert, :count)
      expect(result.alerts).to be_empty
    end
  end

  context "when the template is edited after a copy" do
    let(:earlier_wallet) { create(:catalog_wallet, organization:) }

    before do
      described_class.call!(plan_wallet: load_plan_wallet, catalog_wallet: earlier_wallet)
      UsageMonitoring::CatalogWalletAlerts::UpdateService.call!(alert: template, params: {name: "Running low", thresholds: [{value: "500"}]})
    end

    it "keeps the earlier copy as it was" do
      result

      copy = earlier_wallet.alerts.sole
      expect(copy.name).to eq("Low balance")
      expect(copy.thresholds.pluck(:value)).to contain_exactly(2_000, 10_000)
    end

    it "gives a wallet copied later the edited version" do
      copy = result.alerts.sole

      expect(copy.name).to eq("Running low")
      expect(copy.thresholds.pluck(:code, :value, :recurring)).to eq([[nil, 500, false]])
    end
  end

  context "when the template is deleted after a copy" do
    let(:earlier_wallet) { create(:catalog_wallet, organization:) }

    before do
      described_class.call!(plan_wallet: load_plan_wallet, catalog_wallet: earlier_wallet)
      UsageMonitoring::CatalogWalletAlerts::DestroyService.call!(alert: template)
    end

    it "keeps the earlier copy" do
      result

      expect(earlier_wallet.alerts.sole.thresholds.count).to eq(2)
    end

    it "gives a wallet copied later no alert" do
      expect(result.alerts).to be_empty
      expect(catalog_wallet.alerts).to be_empty
    end
  end

  # Each copy reads the plan wallet again with its templates, as Contracts::MaterializeWalletsService does under its lock
  def load_plan_wallet
    PlanWallet.includes(alerts: :thresholds).find(plan_wallet.id)
  end
end
