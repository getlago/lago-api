# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::ResolveRatePhasesService do
  subject(:result) { described_class.call(contract_rate_card:, plan_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { nil }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:)
  end

  context "with contract-level phases" do
    let!(:intro_phase) do
      create(
        :rate_phase,
        :contract_level,
        organization:,
        contract_rate_card:,
        position: 1,
        billing_interval_cycle_count: 2
      )
    end
    let!(:standard_phase) do
      create(
        :rate_phase,
        :contract_level,
        organization:,
        contract_rate_card:,
        position: 2,
        billing_interval_cycle_count: nil
      )
    end

    it "returns the card's phases in position order" do
      expect(result.rate_phases).to eq([intro_phase, standard_phase])
    end
  end

  context "without contract-level phases" do
    let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:) }
    let!(:plan_phase) do
      create(
        :rate_phase,
        organization:,
        plan_rate_card:,
        position: 1,
        billing_interval_cycle_count: nil
      )
    end

    it "falls back to the plan entry's phases" do
      expect(result.rate_phases).to eq([plan_phase])
    end
  end

  # Neither the card nor a plan entry carries phases, and a card off a plan has no entry
  # to fall back to at all.
  context "without any phases" do
    it "returns none" do
      expect(result.rate_phases).to be_empty
    end
  end
end
