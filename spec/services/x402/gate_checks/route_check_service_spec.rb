# frozen_string_literal: true

require "rails_helper"

describe X402::GateChecks::RouteCheckService, :premium do
  subject(:result) { described_class.call(organization:, plan_code:, billable_metric_code:) }

  let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan_code) { plan.code }
  let(:billable_metric_code) { billable_metric.code }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true) }

  before { charge }

  context "with a usage-only USD plan whose route charges target the wallet" do
    it "returns the parent plan" do
      expect(result.plan).to eq(plan)
    end
  end

  context "with an override of the plan carrying a base fee in EUR" do
    before { create(:plan, organization:, parent: plan, code: plan.code, amount_cents: 500, amount_currency: "EUR") }

    it "reads the parent plan" do
      expect(result.plan).to eq(plan)
    end
  end

  context "with an unknown plan code" do
    let(:plan_code) { "unknown" }

    it "fails with plan_not_found" do
      expect(result.error.error_code).to eq("plan_not_found")
    end
  end

  context "with a metric the plan has no charge for" do
    let(:billable_metric_code) { create(:billable_metric, organization:).code }

    it "fails with charge_not_found" do
      expect(result.error.error_code).to eq("charge_not_found")
    end
  end

  context "with a discarded route charge" do
    let(:charge) { create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true, deleted_at: Time.current) }

    it "fails with charge_not_found" do
      expect(result.error.error_code).to eq("charge_not_found")
    end
  end

  context "with a EUR plan" do
    let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "EUR") }

    it "refuses with plan_currency_not_supported" do
      expect(result.error.messages).to eq(base: ["plan_currency_not_supported"])
    end
  end

  context "with a base fee" do
    let(:plan) { create(:plan, organization:, amount_cents: 1_000, amount_currency: "USD") }

    it "refuses with plan_not_usage_only" do
      expect(result.error.messages).to eq(base: ["plan_not_usage_only"])
    end
  end

  context "with a fixed charge" do
    before { create(:fixed_charge, plan:) }

    it "refuses with plan_not_usage_only" do
      expect(result.error.messages).to eq(base: ["plan_not_usage_only"])
    end
  end

  context "with a discarded fixed charge" do
    before { create(:fixed_charge, plan:, deleted_at: Time.current) }

    it "passes" do
      expect(result).to be_success
    end
  end

  context "with a minimum commitment" do
    before { create(:commitment, :minimum_commitment, plan:) }

    it "refuses with plan_not_usage_only" do
      expect(result.error.messages).to eq(base: ["plan_not_usage_only"])
    end
  end

  context "with a charge minimum on another metric of the plan" do
    before { create(:standard_charge, plan:, billable_metric: create(:billable_metric, organization:), min_amount_cents: 100) }

    it "refuses with plan_not_usage_only" do
      expect(result.error.messages).to eq(base: ["plan_not_usage_only"])
    end
  end

  context "with a second route charge that does not accept a target wallet" do
    before { create(:standard_charge, plan:, billable_metric:) }

    it "refuses with charge_not_targeted" do
      expect(result.error.messages).to eq(base: ["charge_not_targeted"])
    end
  end

  context "without the events targeting integration" do
    before { allow(organization).to receive(:events_targeting_wallets_enabled?).and_return(false) }

    it "refuses with charge_not_targeted" do
      expect(result.error.messages).to eq(base: ["charge_not_targeted"])
    end
  end

  context "with a pay-in-advance route charge that is not invoiceable" do
    let(:charge) { create(:standard_charge, :regroup_paid_fees, plan:, billable_metric:, accepts_target_wallet: true) }

    it "refuses with charge_not_invoiceable" do
      expect(result.error.messages).to eq(base: ["charge_not_invoiceable"])
    end
  end

  context "with an invoiceable pay-in-advance route charge" do
    let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, accepts_target_wallet: true) }

    it "passes" do
      expect(result).to be_success
    end
  end
end
