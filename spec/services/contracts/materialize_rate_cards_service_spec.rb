# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::MaterializeRateCardsService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, :product_catalog, organization:) }
  let(:contract) { create(:contract, organization:, customer:, plan:, started_at: Time.zone.parse("2026-10-01")) }

  let(:rate_card) { create(:rate_card, organization:) }

  before do
    create(:plan_rate_card, organization:, plan:, rate_card:, units: 5)
  end

  it "materializes one contract rate card per plan rate card" do
    expect { result }.to change(ContractRateCard, :count).by(1)

    card = contract.reload.applied_rate_cards.sole
    expect(card).to have_attributes(rate_card:, units: 5)
    expect(card.effective_date).to eq(Date.new(2026, 10, 1))
    expect(card.billing_anchor_date).to eq(Date.new(2026, 10, 1))
    expect(card.next_billing_at).to eq(contract.started_at)
    expect(result.contract_rate_cards).to eq([card])
  end

  context "when the contract carries its own billing anchor" do
    let(:contract) do
      create(
        :contract,
        organization:,
        customer:,
        plan:,
        started_at: Time.zone.parse("2026-10-15"),
        billing_anchor_date: Date.new(2026, 10, 1)
      )
    end

    it "materializes cards on the contract's anchor, not its start date" do
      result

      expect(contract.reload.applied_rate_cards.sole.billing_anchor_date).to eq(Date.new(2026, 10, 1))
    end
  end

  it "does not copy the plan entry's phases: pricing resolves by reference" do
    plan_rate_card = plan.applied_rate_cards.sole
    create(:rate_phase, organization:, plan_rate_card:, position: 1)

    expect { result }.not_to change(RatePhase, :count)
    expect(contract.reload.applied_rate_cards.sole.rate_phases).to be_empty
  end

  context "when the contract has no plan" do
    let(:contract) { create(:contract, organization:, customer:, plan: nil) }

    it "materializes nothing" do
      expect { result }.not_to change(ContractRateCard, :count)
      expect(result.contract_rate_cards).to be_nil
    end
  end
end
