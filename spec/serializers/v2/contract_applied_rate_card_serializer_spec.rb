# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractAppliedRateCardSerializer do
  subject(:payload) { described_class.new(contract_rate_card).serialize }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, catalog_plan:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:) }

  before { create(:rate_phase, organization:, plan_rate_card:, code: "default", position: 1) }

  it "counts the resolved phases, falling back to the plan entry's" do
    expect(payload[:rate_phases_count]).to eq(1)
  end

  context "with phases of its own" do
    before do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "p1", position: 1)
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "p2", position: 2)
    end

    it "counts only the card's own phases" do
      expect(payload[:rate_phases_count]).to eq(2)
    end
  end
end
