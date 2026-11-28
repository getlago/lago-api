# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::CreateService do
  subject(:result) { described_class.call(**attributes) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:started_at) { Time.utc(2026, 6, 6) }
  let(:cycle_started_at) { started_at - 5.days }
  let(:ended_at) { started_at + 15.days }
  let(:rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card, effective_from: started_at) }
  let(:override) { create(:rate_override, organization:) }
  let(:calendar) do
    Billing::Calendar.new(anchor_date: Date.new(2026, 6, 1), interval: Billing::Interval.new(count: 1, unit: :month), timezone: "UTC")
  end
  let(:cycle) do
    Billing::Cycle.new(
      index: 0, started_at: cycle_started_at, ended_at: Time.utc(2026, 7, 1), calendar:,
      phase: Billing::Phase.new(code: "intro", billing_interval_cycle_count: 1, rate_override: override)
    )
  end
  let(:segments) { [Billing::Segments::Segment.new(started_at:, ended_at:, rate:)] }
  let(:terms) { Billing::Terms.new(timing: :advance, prorated: true) }
  let(:obligation) { Billing::Obligation.new(cycle:, segments:, billing_at: started_at, terms:) }
  let(:planned_operation) do
    BillingOperations::Schedule::PlannedOperation.from_obligation(obligation)
  end
  let(:attributes) do
    {
      contract_rate_card:,
      action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage),
      reason: BillingOperation::REASONS.fetch(:rate_change),
      planned_operation:
    }
  end

  it "creates an operation with its identity, cause, action and planned dates" do
    expect(result).to be_success
    expect(result.operation.reload).to have_attributes(
      organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
      reason: "rate_change", billing_at: started_at,
      target_cycle_started_at: cycle_started_at, processed_at: nil, coverage_started_at: started_at, coverage_ended_at: ended_at
    )
    expect(result.operation.segments.sole).to have_attributes(
      organization:, position: 0, started_at:, ended_at:, rate_card_rate: rate, rate_override: override,
      proration_ratio: BigDecimal("0.5") # 15 priced days out of 30 in June
    )
  end

  context "when the obligation spans a rate change" do
    let(:next_ended_at) { ended_at + 6.days }
    let(:next_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card, effective_from: ended_at) }
    let(:segments) do
      super() + [Billing::Segments::Segment.new(started_at: ended_at, ended_at: next_ended_at, rate: next_rate)]
    end

    it "saves one operation covering both segments and snapshots each in coverage order" do
      expect(result).to be_success
      expect(result.operation.reload).to have_attributes(coverage_started_at: started_at, coverage_ended_at: next_ended_at)
      expect(result.operation.segments).to match([
        have_attributes(
          organization:, position: 0, started_at:, ended_at:, rate_card_rate: rate, rate_override: override,
          proration_ratio: BigDecimal("0.5") # 15 priced days out of 30 in June
        ),
        have_attributes(
          organization:, position: 1, started_at: ended_at, ended_at: next_ended_at, rate_card_rate: next_rate, rate_override: override,
          proration_ratio: BigDecimal("0.2") # 6 priced days out of 30 in June
        )
      ])
    end
  end

  it "allows duplicate operations to be created" do
    existing = described_class.call(**attributes).operation

    expect(result).to be_success
    expect(result.operation).not_to eq(existing)
    expect(contract_rate_card.billing_operations.count).to eq(2)
  end

  context "when the contract rate card is missing" do
    let(:attributes) { super().merge(contract_rate_card: nil) }

    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(BillingOperation.count).to eq(0)
    end
  end

  [
    [:action_type, "invalid_action"],
    [:reason, "invalid_causation"],
    [:billing_at, nil]
  ].each do |attribute, value|
    context "when #{attribute} is invalid" do
      let(:attributes) do
        if attribute == :billing_at
          super().merge(planned_operation: planned_operation.with(**{attribute => value}))
        else
          super().merge(attribute => value)
        end
      end

      it "returns a validation failure without creating an operation" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(contract_rate_card.billing_operations).to be_empty
      end
    end
  end

  context "when the planned cycle start is missing" do
    let(:cycle_started_at) { nil }

    it "saves neither the invalid operation nor its segment" do
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(contract_rate_card.billing_operations).to be_empty
      expect(BillingOperationSegment.where(organization:)).to be_empty
    end
  end

  context "when the planned segment is invalid" do
    let(:ended_at) { started_at }

    it "saves neither the operation nor its invalid segment" do
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(contract_rate_card.billing_operations).to be_empty
      expect(BillingOperationSegment.where(organization:)).to be_empty
    end
  end
end
