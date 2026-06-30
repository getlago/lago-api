# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCardsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:plan) { create(:plan, organization:) }
  let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }
  let!(:other_plan_rate_card) { create(:plan_rate_card, organization:) }

  it "returns all plan product items of the organization" do
    expect(result).to be_success
    expect(result.plan_rate_cards).to match_array([plan_rate_card, other_plan_rate_card])
  end

  context "when filtering by plan_id" do
    let(:filters) { {plan_id: plan.id} }

    it "returns only the plan's product items" do
      expect(result.plan_rate_cards).to eq([plan_rate_card])
    end
  end

  context "when filtering by plan_code" do
    let(:filters) { {plan_code: plan.code} }

    it "returns only the plan's product items" do
      expect(result.plan_rate_cards).to eq([plan_rate_card])
    end
  end
end
