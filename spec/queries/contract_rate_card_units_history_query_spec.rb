# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCardUnitsHistoryQuery do
  subject(:result) { described_class.call(organization:, contract_rate_cards: cards) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:first_card) { create(:contract_rate_card, organization:, contract:, units: 8, effective_date: Date.new(2026, 9, 1)) }
  let(:second_card) { create(:contract_rate_card, organization:, contract:, units: 4, effective_date: Date.new(2026, 9, 1)) }
  let(:other_card) { create(:contract_rate_card, units: 20) }
  let(:cards) { [first_card, second_card, other_card] }
  let(:timestamp) { Time.utc(2026, 9, 15, 12, 30, 0, 123456) }
  let(:change) do
    create(:billing_operation, organization:, customer:, contract_rate_card: first_card, action_type: "reconcile_advance_coverage",
      units_before: 8, units_after: 5, billing_at: timestamp)
  end

  before do
    cards
    change
    create(:billing_operation, organization:, customer:, contract_rate_card: first_card, action_type: "reconcile_advance_coverage",
      reason: :rate_change, billing_at: timestamp + 1.hour, units_before: 5, units_after: 99)
    create(:billing_operation, organization:, customer:, contract_rate_card: first_card, action_type: "close_fixed_arrears",
      reason: :contract_units_change, billing_at: timestamp + 30.minutes)
    create(:billing_operation, organization:, customer: second_card.contract.customer, contract_rate_card: second_card, action_type: "reconcile_advance_coverage",
      units_before: 4, units_after: 6, billing_at: timestamp)
  end

  it "loads only quantity history in one query for the requested organization" do
    queries = capture_sql { result }
    history_queries = queries.grep(/FROM "billing_operations"/)

    expect(history_queries.size).to eq(1)
    expect(history_queries.sole).to include('"billing_operations"."units_after"')
    expect(result.histories.keys).to match_array([first_card.id, second_card.id])
    expect(result.histories.fetch(first_card.id).units_at(timestamp + 2.hours)).to eq(5)
    expect(result.histories.fetch(second_card.id).units_at(timestamp)).to eq(6)
  end

  it "keeps the association usable as complete model records" do
    expect(first_card.units_changes.count).to eq(1)
    expect(first_card.units_changes.sole).to have_attributes(action_type: "reconcile_advance_coverage", units_after: 5)
    expect(first_card.units_changes.sole).not_to be_readonly
  end

  context "when customers have their own timezone" do
    let(:cards) { ContractRateCard.where(id: [first_card.id, second_card.id]).to_a }

    it "does not load billing entities to resolve units history" do
      queries = capture_sql { result }

      expect(queries.grep(/FROM "billing_entities"/)).to be_empty
      expect(result.histories.fetch(first_card.id).units_at(timestamp)).to eq(5)
    end
  end

  context "when customers inherit their billing entity timezone" do
    let(:billing_entity) { create(:billing_entity, organization:, timezone: "America/New_York") }
    let(:customer) { create(:customer, organization:, billing_entity:, timezone: nil) }
    let(:second_customer) do
      create(:customer, organization:, billing_entity: create(:billing_entity, organization:, timezone: "Asia/Tokyo"), timezone: nil)
    end
    let(:second_card) do
      create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer: second_customer),
        units: 4, effective_date: Date.new(2026, 9, 1))
    end
    let(:cards) { ContractRateCard.where(id: [first_card.id, second_card.id]).to_a }

    it "loads billing entities together and uses each customer's local midnight" do
      queries = capture_sql { result }

      expect(queries.grep(/FROM "billing_entities"/).size).to eq(1)
      expect(result.histories.fetch(first_card.id).units_at(Time.utc(2026, 9, 1, 3))).to be_nil
      expect(result.histories.fetch(first_card.id).units_at(Time.utc(2026, 9, 1, 4))).to eq(8)
      expect(result.histories.fetch(second_card.id).units_at(Time.utc(2026, 8, 31, 15))).to eq(4)
    end
  end

  context "with scheduled units on several cards" do
    before do
      [first_card, second_card].each do |card|
        card.update!(billing_anchor_date: Date.new(2026, 9, 1))
        create(:rate_card_rate, organization:, rate_card: card.rate_card, effective_from: Time.utc(2026, 9, 1))
        create(:contract_rate_card_term, organization:, contract_rate_card: card, units: 7,
          effective_date: Date.new(2026, 9, 10), created_at: Time.utc(2026, 9, 10), application_timing: :next_billing_cycle)
      end
    end

    it "loads rate timelines together and resolves each scheduled boundary" do
      queries = capture_sql { result }

      expect(queries.grep(/FROM "rate_card_rates"/).size).to eq(1)
      expect(result.histories.values.map { it.scheduled_term_at(timestamp).starts_at }).to eq([Time.utc(2026, 10, 1)] * 2)
      expect(result.histories.values.map { it.units_at(Time.utc(2026, 10, 1)) }).to eq([7, 7])
    end
  end

  context "without cards" do
    let(:cards) { [] }
    let(:change) { nil }

    it "returns no histories without querying operations" do
      queries = capture_sql { result }

      expect(result.histories).to eq({})
      expect(queries.grep(/FROM "billing_operations"/)).to be_empty
    end
  end
end
