# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::CreateService do
  subject(:result) { described_class.call(**attributes) }

  let(:organization) { create(:organization) }
  let(:started_at) { Time.utc(2026, 11, 1) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: started_at) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance") }
  let(:billing_scope) { "cycle" }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: started_at.to_date, billing_anchor_date: started_at.to_date)
  end
  let(:planned_operation) do
    first_rate
    second_rate
    schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
    BillingOperations::Schedule::BuildPlannedOperation.call!(schedule:, at: started_at).planned_operation
  end

  let(:first_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
      billing_interval_count: 1, billing_interval_unit: "month")
  end
  let(:second_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15),
      billing_interval_count: 1, billing_interval_unit: "month")
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
    expect(result.operation).to have_attributes(
      organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
      reason: "rate_change", billing_at: started_at,
      target_cycle_started_at: started_at, processed_at: nil
    )
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

  it "stores the full cycle's half-open coverage" do
    expect(result.operation.reload).to have_attributes(
      coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 12, 1)
    )
    expect(result.operation.segments.pluck(:position, :started_at, :ended_at, :rate_card_rate_id, :rate_override_id)).to eq([
      [0, Time.utc(2026, 11, 1), Time.utc(2026, 11, 15), first_rate.id, nil],
      [1, Time.utc(2026, 11, 15), Time.utc(2026, 12, 1), second_rate.id, nil]
    ])
  end

  context "with a phase override" do
    let(:override) { create(:rate_override, organization:) }

    before { create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override) }

    it "retains the catalog rate and the applicable override" do
      expect(result.operation.reload.segments.pluck(:rate_card_rate_id, :rate_override_id)).to eq([
        [first_rate.id, override.id], [second_rate.id, override.id]
      ])
    end
  end

  context "when the plan is used for a different rate card" do
    let(:attributes) { super().merge(contract_rate_card: create(:contract_rate_card, organization:, contract:)) }

    it "saves neither the operation nor its segments" do
      expect(result).to be_failure
      expect(BillingOperation.where(organization:)).to be_empty
      expect(BillingOperationSegment.where(organization:)).to be_empty
    end
  end

  context "with segment scope" do
    let(:billing_scope) { "segment" }

    it "stores only the first segment's half-open coverage" do
      expect(result.operation.reload).to have_attributes(
        coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 11, 15)
      )
      expect(result.operation.segments.sole.rate_card_rate_id).to eq(first_rate.id)
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

  context "with an explicitly planned obligation" do
    let(:started_at) { Time.utc(2026, 6, 6) }
    let(:cycle_started_at) { started_at - 5.days }
    let(:ended_at) { started_at + 15.days }
    let(:rate) { first_rate }
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
end
