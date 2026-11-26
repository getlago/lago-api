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
    create(:billing_operation, organization:, customer:, contract_rate_card: second_card, action_type: "reconcile_advance_coverage",
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
