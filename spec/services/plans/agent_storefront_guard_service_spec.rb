# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::AgentStorefrontGuardService do
  subject(:result) { described_class.call(plan:) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:storefront, refind: true) { create(:agent_storefront_integration, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0) }

  context "when no storefront sells the plan" do
    before { plan.update!(amount_cents: 1000) }

    it "passes" do
      expect(result).to be_success
    end
  end

  context "when a storefront sells the plan" do
    before { storefront.update!(plans: [{plan_code: plan.code}]) }

    it "passes while the plan is usage-only" do
      expect(result).to be_success
    end

    it "refuses a subscription fee, a minimum commitment, a fixed charge or a charge minimum" do
      plans = Array.new(4) { create(:plan, organization:, amount_cents: 0) }
      storefront.update!(plans: plans.map { {plan_code: it.code} })
      plans[0].update!(amount_cents: 1000)
      create(:commitment, plan: plans[1])
      create(:fixed_charge, plan: plans[2])
      create(:standard_charge, plan: plans[3], min_amount_cents: 100)

      plans.each do |plan|
        result = described_class.call(plan:)

        expect(result).not_to be_success
        expect(result.error.code).to eq("plan_sold_by_agent_storefront")
      end
    end

    it "passes an override of the plan, which no storefront sells" do
      child = create(:plan, organization:, parent: plan, code: plan.code, amount_cents: 1000)

      expect(described_class.call(plan: child)).to be_success
    end
  end
end
