# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::SeedLifecycleService do
  subject(:result) { described_class.call(contract_rate_card:, billing_anchor_date:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-11-15")) }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      effective_date: Date.new(2026, 10, 1),
      billing_anchor_date: Date.new(2026, 10, 1)
    )
  end
  let(:unit) do
    create(:contract_rate_card_term, organization:, contract_rate_card:, units: 12, effective_date: contract_rate_card.effective_date)
  end
  let(:billing_anchor_date) { nil }

  around { |example| travel_to(Time.zone.parse("2026-09-30T12:00:00Z")) { example.run } }

  it "starts the card with its contract" do
    unit

    expect(result).to be_success
    expect(contract_rate_card.reload).to have_attributes(
      effective_date: Date.new(2026, 11, 15),
      billing_anchor_date: Date.new(2026, 11, 15)
    )
    expect(unit.reload).to have_attributes(units: 12, effective_date: Date.new(2026, 11, 15))
  end

  context "with a later-dated unit" do
    let(:later_unit) { create(:contract_rate_card_term, organization:, contract_rate_card:, units: 25, effective_date: Date.new(2026, 12, 1)) }

    before do
      unit
      later_unit
    end

    it "moves only the initial unit row when reseeding the card date" do
      expect(result).to be_success

      expect(contract_rate_card.terms.order(:effective_date).pluck(:effective_date, :units)).to eq([
        [Date.new(2026, 11, 15), 12],
        [Date.new(2026, 12, 1), 25]
      ])
      expect(later_unit.reload.effective_date).to eq(Date.new(2026, 12, 1))
    end
  end

  context "when a later unit already has the new card date" do
    let(:later_unit) { create(:contract_rate_card_term, organization:, contract_rate_card:, units: 25, effective_date: Date.new(2026, 11, 15)) }

    before do
      unit
      later_unit
    end

    it "returns a validation failure and rolls back both date changes" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.effective_date).to eq(Date.new(2026, 10, 1))
      expect(unit.reload.effective_date).to eq(Date.new(2026, 10, 1))
      expect(later_unit.reload.effective_date).to eq(Date.new(2026, 11, 15))
    end
  end

  context "when reseeding only the billing anchor" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-10-01")) }
    let(:billing_anchor_date) { Date.new(2026, 10, 15) }

    it "leaves the unit date unchanged" do
      unit

      expect(result).to be_success
      expect(unit.reload.effective_date).to eq(Date.new(2026, 10, 1))
    end
  end

  context "with a customer timezone" do
    let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-11-15T02:00:00Z")) }

    it "syncs the unit to the customer-local effective date" do
      unit

      expect(result).to be_success
      expect(contract_rate_card.reload.effective_date).to eq(Date.new(2026, 11, 14))
      expect(unit.reload.effective_date).to eq(Date.new(2026, 11, 14))
    end
  end

  context "with an anchor of the card's own" do
    let(:billing_anchor_date) { Date.new(2026, 11, 1) }

    it "keeps it" do
      result

      expect(contract_rate_card.reload.billing_anchor_date).to eq(Date.new(2026, 11, 1))
    end
  end

  context "when the contract started in the past" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-08-15")) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-08-01"))
      create(:rate_phase, :contract_level, organization:, contract_rate_card:)
    end

    it "waits for the billing date of the current period, its end on an arrears card" do
      result

      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-15"))
    end
  end
end
