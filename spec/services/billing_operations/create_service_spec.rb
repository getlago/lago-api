# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::CreateService do
  subject(:result) { described_class.call(**attributes) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:started_at) { Time.zone.parse("2026-10-01") }
  let(:planned_operation) do
    BillingOperations::Schedule::PlannedOperation.new(
      cycle_started_at: started_at, billing_at: started_at,
      coverage_started_at: started_at, coverage_ended_at: started_at + 1.month
    )
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

  context "with a plan built from the schedule" do
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance") }
    let(:billing_scope) { "cycle" }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
        effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1))
    end
    let(:planned_operation) do
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      BillingOperations::Schedule::BuildPlannedOperation.call!(schedule:, at: Time.utc(2026, 11, 1)).planned_operation
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1),
        billing_interval_count: 1, billing_interval_unit: "month")
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15),
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "stores the full cycle's half-open coverage" do
      expect(result.operation.reload).to have_attributes(
        coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 12, 1)
      )
    end

    context "with segment scope" do
      let(:billing_scope) { "segment" }

      it "stores only the first segment's half-open coverage" do
        expect(result.operation.reload).to have_attributes(
          coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 11, 15)
        )
      end
    end
  end

  [
    [:action_type, "invalid_action"],
    [:reason, "invalid_causation"],
    [:billing_at, nil],
    [:cycle_started_at, nil],
    [:coverage_started_at, nil],
    [:coverage_ended_at, nil]
  ].each do |attribute, value|
    context "when #{attribute} is invalid" do
      let(:attributes) do
        if [:billing_at, :cycle_started_at, :coverage_started_at, :coverage_ended_at].include?(attribute)
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
end
