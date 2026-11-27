# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::UnitsAtService do
  subject(:result) { described_class.call(contract_rate_card:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, units: 8, effective_date: Date.new(2026, 9, 1), billing_anchor_date: Date.new(2026, 9, 1)) }
  let(:timestamp) { Time.utc(2026, 9, 15, 12, 30) }

  before do
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
      billing_at: Time.utc(2026, 9, 15, 12, 30), units_before: 8, units_after: 5)
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
      billing_at: Time.utc(2026, 9, 15, 13), units_before: 5, units_after: 10)
  end

  it "selects the change at its exact instant and excludes later changes" do
    expect(result.units).to eq(5)
  end

  context "when before the timestamped change" do
    let(:timestamp) { Time.utc(2026, 9, 15, 12, 29, 59) }

    it "uses the earlier quantity" do
      expect(result.units).to eq(8)
    end
  end

  context "when before the customer's local start day" do
    let(:timestamp) { Time.utc(2026, 9, 1, 3, 59, 59) }

    it "does not apply the legacy date in UTC" do
      expect(result.units).to be_nil
    end
  end

  context "with prepared history" do
    subject(:result) { described_class.call(contract_rate_card:, timestamp:, history:) }

    let(:history) { ContractRateCardUnitsHistoryQuery.call!(organization:, contract_rate_cards: [contract_rate_card]).histories.fetch(contract_rate_card.id) }

    before { history }

    it "uses the same ordering without another terms query" do
      queries = capture_sql { expect(result.units).to eq(5) }
      expect(queries.grep(/FROM "(?:contract_rate_cards_terms|billing_operations)"/i)).to be_empty
    end
  end

  context "with a scheduled units change" do
    let(:scheduled_at) { Time.utc(2026, 10, 1, 4) }
    let(:term_created_at) { Time.utc(2026, 9, 10) }

    before do
      create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card, effective_from: Time.utc(2026, 9, 1))
      create(:contract_rate_card_term, organization:, contract_rate_card:, units: 12, effective_date: Date.new(2026, 9, 10), created_at: term_created_at, application_timing: :next_billing_cycle)
    end

    it "returns the scheduled quantity without applying it early" do
      expect(result.units).to eq(5)
      expect(result.scheduled_term).to have_attributes(units: 12, effective_date: Date.new(2026, 9, 10), starts_at: scheduled_at)
    end

    context "when the creation timestamp differs from the effective date" do
      let(:term_created_at) { Time.utc(2026, 10, 5) }

      it "resolves the scheduled boundary from the effective date" do
        expect(result.scheduled_term.starts_at).to eq(scheduled_at)
        expect(described_class.call!(contract_rate_card:, timestamp: scheduled_at).units).to eq(12)
      end
    end

    context "when the scheduled instant is reached" do
      let(:timestamp) { scheduled_at }

      it "returns the scheduled quantity as current and no future change" do
        expect(result.units).to eq(12)
        expect(result.scheduled_term).to be_nil
      end
    end

    context "with an immediate change at the scheduled boundary" do
      let(:timestamp) { scheduled_at }

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
          billing_at: scheduled_at, units_before: 12, units_after: 7)
      end

      it "applies the immediate change once at the exact instant" do
        expect(result.units).to eq(7)
        expect(result.units_by_timestamp.keys.count { it == scheduled_at }).to eq(1)
      end
    end
  end

  context "when reconciliation has already completed without an invoice" do
    before do
      contract_rate_card.billing_operations.find_by!(action_type: "reconcile_advance_coverage", billing_at: timestamp)
        .update!(processed_at: timestamp + 1.hour)
    end

    it "retains the original quantity change as history" do
      expect(result.units).to eq(5)
    end
  end

  context "when billing work is cancelled" do
    before do
      contract_rate_card.billing_operations.find_by!(action_type: "reconcile_advance_coverage", billing_at: timestamp)
        .update!(cancelled_at: timestamp + 1.hour, cancellation_reason: :rate_change)
    end

    it "retains the recorded units independently of the billing work" do
      expect(result.units).to eq(5)
    end
  end
end
