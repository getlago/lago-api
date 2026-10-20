# frozen_string_literal: true

require "rails_helper"

describe X402::PlanEligibility do
  describe ".refusal" do
    subject(:refusal) { described_class.refusal(plan) }

    let(:plan) { create(:plan, amount_cents: 0, amount_currency: "USD") }

    it "is nil for a usage-only USD plan" do
      expect(refusal).to be_nil
    end

    context "with a EUR plan" do
      let(:plan) { create(:plan, amount_cents: 0, amount_currency: "EUR") }

      it "is plan_currency_not_supported" do
        expect(refusal).to eq("plan_currency_not_supported")
      end
    end

    context "with a minimum commitment" do
      before { create(:commitment, :minimum_commitment, plan:) }

      it "is plan_not_usage_only" do
        expect(refusal).to eq("plan_not_usage_only")
      end
    end
  end
end
