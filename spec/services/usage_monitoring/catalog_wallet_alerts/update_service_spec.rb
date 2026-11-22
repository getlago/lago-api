# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::UpdateService do
  subject(:result) { described_class.call(alert:, params:) }

  let_it_be(:organization) { create(:organization) }

  let(:alert) { create(:plan_wallet_alert, organization:, alert_type: "balance", code: "low_balance", name: "Low balance") }
  let(:params) { {name: "Running low", thresholds: [{code: "low", value: "5000"}, {value: "0"}]} }

  # Through the alert's own association, which holds a template's thresholds as well as a contract wallet alert's
  before { alert.thresholds.create!(organization:, code: "low", value: 10_000, notify_on: %w[triggered resolved]) }

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

  context "with a name that is a list" do
    let(:params) { {name: ["Running low"]} }

    it "fails and keeps the name" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({name: ["value_is_invalid"]})
      expect(alert.reload.name).to eq("Low balance")
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

  context "with an alert on a contract wallet" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, :pending, customer:) }
    let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:) }
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }

    context "when the alert is watching the balance" do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", previous_value: 1_500, last_processed_at: 1.hour.ago) }
      let(:params) { {thresholds: [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}, {code: "low", value: "1000", notify_on: %w[triggered resolved]}]} }

      it "seeds the opted-in line the edit puts in alarm and sends nothing" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).to be_success
        # 2000 is above the balance of 1500, so it is in alarm; 1000 is below it
        seeded = alert.all_triggered_alerts.sole
        expect(seeded).to have_attributes(kind: "seeded", catalog_wallet:, current_value: 1_500, previous_value: 1_500)
        expect(seeded.crossed_thresholds).to eq([{"code" => "warning", "value" => "2000.0", "recurring" => false}])
      end
    end

    context "when an ongoing balance alert started on an empty wallet" do
      let(:contract) { create(:contract, customer:) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance", previous_value: 0, last_processed_at: 1.hour.ago) }
      # The same line as before, opted in and in alarm at 0
      let(:params) { {thresholds: [{code: "low", value: "10000", notify_on: %w[triggered resolved]}]} }

      it "seeds nothing, as its baseline did" do
        expect(result).to be_success
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    it "updates the name and replaces the thresholds, recording and sending nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)

      expect(result).to be_success
      expect(result.alert).to eq(alert)
      expect(alert.reload).to have_attributes(name: "Running low", previous_value: nil, last_processed_at: nil)
      expect(alert.thresholds.order(:value).pluck(:code, :value, :notify_on)).to eq([
        [nil, 0, %w[triggered]],
        ["low", 5000, %w[triggered resolved]]
      ])
      expect(alert.all_triggered_alerts).to be_empty
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, customer:) }

      it "updates the alert" do
        expect(result).to be_success
        expect(alert.reload.name).to eq("Running low")
      end
    end

    context "when the wallet has ended" do
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, terminated_at: Time.current) }

      it "refuses the write and keeps the alert as it was" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("wallet_alerts_read_only")
        expect(alert.reload.name).to eq("Low balance")
        expect(alert.thresholds.pluck(:value)).to eq([10_000])
      end
    end

    context "when the contract was canceled after the alert was loaded" do
      before { Contracts::TerminateService.call!(contract: Contract.find(contract.id)) }

      it "refuses the write" do
        expect(result).to be_failure
        expect(result.error.code).to eq("contract_not_live")
      end
    end

    context "when the wallet was deleted before the lock" do
      before { CatalogWallet.find(catalog_wallet.id).discard! }

      it "fails and keeps the alert as it was" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("contract_wallet_not_found")
        expect(alert.reload.name).to eq("Low balance")
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
