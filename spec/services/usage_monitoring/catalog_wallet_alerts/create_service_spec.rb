# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::CreateService do
  subject(:result) { described_class.call(plan_wallet:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:plan_wallet, refind: true) { create(:plan_wallet, organization:) }

  let(:params) do
    {
      alert_type: "balance",
      code: "low_balance",
      name: "Low balance",
      thresholds: [
        {code: "low", value: "10000", notify_on: %w[triggered resolved]},
        {code: "empty", value: "0"}
      ]
    }
  end

  it "creates the template and its thresholds" do
    expect(result).to be_success
    expect(result.alert).to be_persisted
    expect(result.alert).to have_attributes(organization:, plan_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance")
    expect(result.alert.thresholds.order(:value).pluck(:organization_id, :code, :value, :recurring, :notify_on)).to eq([
      [organization.id, "empty", 0, false, %w[triggered]],
      [organization.id, "low", 10_000, false, %w[triggered resolved]]
    ])
  end

  context "with a recurring threshold" do
    before { params[:thresholds] = [{code: "low", value: "10000"}, {code: "every_50", value: 5000, recurring: true}] }

    it "creates it" do
      expect(result).to be_success
      expect(result.alert.thresholds.find_by(recurring: true)).to have_attributes(code: "every_50", value: 5000)
    end
  end

  context "with a recurring step whose first line is 0" do
    before { params[:thresholds] = [{value: "5000"}, {value: "5000", recurring: true}] }

    it "creates it, since an empty wallet reaches that line" do
      expect(result).to be_success
    end
  end

  context "with a recurring step on its own" do
    # Its first line sits one step below 0, which a balance never reaches
    before { params[:thresholds] = [{value: "5000", recurring: true}] }

    it "fails and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a recurring step larger than the lowest threshold" do
    # Its first line is 1000 - 5000 = -4000
    before { params[:thresholds] = [{value: "1000"}, {value: "5000", recurring: true}] }

    it "fails and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a recurring step on its own on an ongoing balance alert" do
    before { params.merge!(alert_type: "ongoing_balance", thresholds: [{value: "5000", recurring: true}]) }

    it "creates it, since unbilled usage can take the ongoing balance below 0" do
      expect(result).to be_success
    end
  end

  context "without a plan wallet" do
    let(:plan_wallet) { nil }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("plan_wallet_not_found")
    end
  end

  context "when the plan wallet was deleted before the lock" do
    # Another request deletes it: the instance the service holds stays kept until the lock reloads it
    before { PlanWallet.find(plan_wallet.id).discard! }

    it "fails and writes nothing on it" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("plan_wallet_not_found")
      expect(UsageMonitoring::PlanWalletAlert.where(plan_wallet_id: plan_wallet.id)).to be_empty
    end
  end

  context "without an alert type" do
    before { params.delete(:alert_type) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({alert_type: ["value_is_mandatory"]})
    end
  end

  context "with an unknown alert type" do
    before { params[:alert_type] = "usage_amount" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({alert_type: ["invalid_type"]})
    end
  end

  context "without thresholds" do
    before { params[:thresholds] = [] }

    it "fails with the shared threshold checks" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
    end
  end

  context "with a fraction of a cent" do
    before { params[:thresholds] = [{value: "10000"}, {value: "10000.5"}] }

    it "fails and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a whole number of cents written as a decimal" do
    before { params[:thresholds] = [{value: "10000.0"}] }

    it "creates the threshold" do
      expect(result).to be_success
      expect(result.alert.thresholds.sole.value).to eq(10_000)
    end
  end

  context "with a negative balance threshold" do
    before { params[:thresholds] = [{value: "10000"}, {value: "-100"}] }

    it "fails and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a negative ongoing balance threshold" do
    before { params.merge!(alert_type: "ongoing_balance", thresholds: [{value: "-100"}]) }

    it "creates it, since unbilled usage can take the ongoing balance below 0" do
      expect(result).to be_success
      expect(result.alert.thresholds.sole.value).to eq(-100)
    end
  end

  {code: ["low_balance"], name: {text: "Low balance"}}.each do |field, value|
    context "with a #{field} that is not a single value" do
      before { params[field] = value }

      it "fails on it and creates nothing" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({field => ["value_is_invalid"]})
        expect(plan_wallet.alerts).to be_empty
      end
    end
  end

  context "with a code that cannot address the alert in its route" do
    before { params[:code] = "low balance" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({code: ["value_is_invalid"]})
    end
  end

  context "when the wallet already has an alert of that type" do
    before { create(:plan_wallet_alert, plan_wallet:, organization:, alert_type: "balance", code: "other") }

    it "fails on the type index" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({base: ["alert_already_exists"]})
    end
  end

  context "when the wallet already has an alert with that code" do
    before { create(:plan_wallet_alert, plan_wallet:, organization:, alert_type: "ongoing_balance", code: "low_balance") }

    it "fails on the code index" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({code: ["value_already_exist"]})
    end
  end
end
