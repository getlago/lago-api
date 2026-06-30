# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCards::UpdateService do
  subject(:result) { described_class.call(plan_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, units: 5) }

  let(:params) { {units: "12"} }

  it "updates the entry" do
    expect(result).to be_success
    expect(result.plan_rate_card.units).to eq(12)
  end

  context "when the plan has subscriptions" do
    before { create(:subscription, plan:, organization:) }

    it "forbids the update" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
    end
  end

  context "when the entry is missing" do
    let(:plan_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan_rate_card")
    end
  end
end
