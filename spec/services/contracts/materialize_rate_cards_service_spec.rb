# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::MaterializeRateCardsService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-01")) }

  let(:rate_card) { create(:rate_card, organization:) }

  before do
    create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 5)
  end

  it "materializes one contract rate card per plan rate card" do
    expect { result }.to change(ContractRateCard, :count).by(1)

    card = contract.reload.applied_rate_cards.sole
    expect(card).to have_attributes(rate_card:, units: 5)
    expect(card.effective_date).to eq(Date.new(2026, 10, 1))
    expect(card.billing_anchor_date).to eq(Date.new(2026, 10, 1))
    expect(card.next_billing_at).to eq(contract.started_at)
    expect(card.rate_phases).to be_empty
    expect(result.contract_rate_cards).to eq([card])
  end

  context "when the contract carries its own billing anchor" do
    let(:contract) do
      create(
        :contract,
        organization:,
        customer:,
        catalog_plan:,
        started_at: Time.zone.parse("2026-10-15"),
        billing_anchor_date: Date.new(2026, 10, 1)
      )
    end

    it "materializes cards on the contract's anchor, not its start date" do
      result

      expect(contract.reload.applied_rate_cards.sole.billing_anchor_date).to eq(Date.new(2026, 10, 1))
    end
  end

  context "when the customer's day differs from UTC at the start instant" do
    let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-01T02:00:00Z")) }

    it "materializes on the customer-local day" do
      result

      card = contract.reload.applied_rate_cards.sole
      expect(card.effective_date).to eq(Date.new(2026, 9, 30))
      expect(card.billing_anchor_date).to eq(Date.new(2026, 9, 30))
    end
  end

  describe "rate phases" do
    let(:plan_rate_card) { catalog_plan.applied_rate_cards.sole }
    let(:rate_override) do
      create(:rate_override, organization:, rate_properties: {"amount" => "1.00"}, billing_interval_count: 1, billing_interval_unit: "week", pricing_unit_conversion_rate: 2.5)
    end

    before do
      create(:rate_phase, organization:, plan_rate_card:, code: "intro", position: 1, name: "Intro", billing_interval_cycle_count: 2, rate_override:)
      create(:rate_phase, organization:, plan_rate_card:, code: "regular", position: 2)
    end

    it "copies the plan entry's timeline onto the card" do
      expect { result }.to change(RatePhase, :count).by(2)

      phases = contract.reload.applied_rate_cards.sole.rate_phases
      expect(phases.map { [it.code, it.position, it.name, it.billing_interval_cycle_count] })
        .to eq([["intro", 1, "Intro", 2], ["regular", 2, nil, nil]])
      expect(phases.map(&:plan_rate_card_id)).to all(be_nil)
    end

    it "gives the copied phase its own override" do
      expect { result }.to change(RateOverride, :count).by(1)

      copy = contract.reload.applied_rate_cards.sole.rate_phases.first.rate_override
      expect(copy).not_to eq(rate_override)
      expect(copy).to have_attributes(
        rate_model: rate_override.rate_model,
        rate_properties: rate_override.rate_properties,
        min_amount_cents: rate_override.min_amount_cents,
        billing_interval_count: 1,
        billing_interval_unit: "week",
        pricing_unit_conversion_rate: 2.5
      )
    end

    it "leaves the plan entry untouched" do
      result

      expect(plan_rate_card.rate_phases.map(&:code)).to eq(%w[intro regular])
      expect(plan_rate_card.rate_phases.first.rate_override).to eq(rate_override)
    end

    context "when the plan has several rate cards" do
      let(:other_rate_card) { create(:rate_card, organization:) }
      let(:other_plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card: other_rate_card) }

      before do
        create(:rate_phase, organization:, plan_rate_card: other_plan_rate_card, code: "trial", position: 1, billing_interval_cycle_count: 1)
      end

      it "copies each entry's phases onto its own card" do
        result

        cards = contract.reload.applied_rate_cards.index_by(&:rate_card_id)
        expect(cards.fetch(rate_card.id).rate_phases.map(&:code)).to eq(%w[intro regular])
        expect(cards.fetch(other_rate_card.id).rate_phases.map(&:code)).to eq(%w[trial])
      end
    end
  end

  context "when the contract has no plan" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan: nil) }

    it "materializes nothing" do
      expect { result }.not_to change(ContractRateCard, :count)
      expect(result.contract_rate_cards).to be_nil
    end
  end

  describe "next_billing_at" do
    subject(:next_billing_at) { result.contract_rate_cards.sole.next_billing_at }

    let(:contract) do
      create(:contract, customer:, catalog_plan:, started_at:, billing_anchor_date: Date.new(2026, 1, 1))
    end
    let(:started_at) { Time.utc(2026, 1, 15, 14, 30) }
    let(:now) { Time.utc(2026, 1, 15, 14, 30) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2025, 1, 1))
    end

    around { |example| travel_to(now) { example.run } }

    it "waits for the first period to close in arrears" do
      expect(next_billing_at).to eq(Time.utc(2026, 2, 1))
    end

    context "when the rate card bills in advance" do
      let(:rate_card) { create(:rate_card, :advance, organization:) }

      # Billable as soon as the cycle opens, and the cycle opens at the start of the
      # signing day rather than at 14:30.
      it "bills from the start of the day the card was signed" do
        expect(next_billing_at).to eq(Time.utc(2026, 1, 15))
      end
    end

    # The contract is backdated by nearly three months. Those periods are not billed:
    # the card joins the calendar at the period it lands in today.
    context "when the contract is backdated" do
      let(:started_at) { Time.utc(2025, 12, 15) }
      let(:now) { Time.utc(2026, 3, 10, 12, 0) }

      it "starts from the current period rather than back-billing the gap" do
        expect(next_billing_at).to eq(Time.utc(2026, 4, 1))
      end
    end

    # QA plan PH3: the first phase sets the cadence, so seeding the clock on the card's own
    # monthly interval would put the first look a whole month late.
    context "when the first rate phase overrides the interval" do
      before do
        create(
          :rate_phase,
          organization:,
          plan_rate_card: catalog_plan.applied_rate_cards.sole,
          position: 1,
          billing_interval_cycle_count: 2,
          rate_override: create(:rate_override, organization:, billing_interval_count: 1, billing_interval_unit: "week")
        )
      end

      it "seeds the clock on the phase's cadence, not the card's" do
        expect(next_billing_at).to eq(Time.utc(2026, 1, 22))
      end
    end
  end
end
