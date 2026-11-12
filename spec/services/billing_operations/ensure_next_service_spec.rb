# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::EnsureNextService do
  subject(:result) { described_class.call(operation:, resolution:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "advance" }
  let(:action_type) { "renew_fixed_advance" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:contract_rate_card) do
    create(
      :contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1)
    )
  end
  let(:operation) do
    create(
      :billing_operation, organization:, contract_rate_card:,
      action_type:, causation_type: "contract_activation",
      billing_at: operation_current_at,
      target_cycle_started_at: target_start
    )
  end
  let(:target_start) { Time.zone.parse("2026-01-01") }
  let(:target_end) { Time.zone.parse("2026-02-01") }
  let(:operation_current_at) { target_start }
  let(:resolution) { BillingOperations::ResolveSegmentsService.call!(operation:) }

  before do
    create(
      :rate_card_rate, organization:, rate_card:, effective_from: target_start,
      billing_interval_count: 1, billing_interval_unit: "month"
    )
  end

  it "resolves continuation from the original target cycle and creates the next cycle" do
    expect(result).to be_success
    expect(result.operation).to have_attributes(
      action_type: "renew_fixed_advance", causation_type: "periodic_continuation",
      billing_at: target_end,
      target_cycle_started_at: target_end
    )
    expect(LegacyBillingSegment.where(contract_rate_card_id: contract_rate_card.id)).to be_empty
  end

  context "with a prepared resolution" do
    before do
      operation
      allow(BillingOperations::BuildScheduleService).to receive(:call!).and_call_original
    end

    it "uses a prepared resolution without rebuilding it" do
      expect(result).to be_success
      expect(BillingOperations::BuildScheduleService).to have_received(:call!).once
      expect(resolution).to have_attributes(schedule: be_present, cycle: be_present)
    end
  end

  context "when the action is not periodic" do
    let(:action_type) { "reconcile_advance_coverage" }
    let(:resolution) { nil }

    it "does not create a successor" do
      expect(result).to be_success
      expect(operation.reload.action_type).to eq("reconcile_advance_coverage")
      expect(result.operation).to be_nil
      expect(contract_rate_card.billing_operations.count).to eq(1)
    end
  end

  context "when a late payment regroup is not continued" do
    let(:action_type) { "regroup_paid_fees" }
    let(:resolution) { nil }

    before { operation.update!(causation_type: "late_payment") }

    it "does not require a resolution or create a successor" do
      expect(result).to be_success
      expect(result.operation).to be_nil
      expect(contract_rate_card.billing_operations.count).to eq(1)
    end
  end

  context "when the target cycle is split by a price change" do
    before do
      create(
        :rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-15"),
        billing_interval_count: 1, billing_interval_unit: "month"
      )
    end

    it "creates the next operation for the later slice in the same cycle" do
      expect(result.operation).to have_attributes(
        billing_at: Time.zone.parse("2026-01-15"),
        target_cycle_started_at: target_start
      )
    end
  end

  context "when the rate card bills fixed arrears" do
    let(:billing_timing) { "arrears" }
    let(:action_type) { "close_fixed_arrears" }
    let(:operation_current_at) { target_end }

    it "uses the next billable cycle rather than interpreting its billing instant as a cycle" do
      expect(result).to be_success
      expect(result.operation).to have_attributes(
        billing_at: Time.zone.parse("2026-03-01"),
        target_cycle_started_at: target_end
      )
    end

    context "when processing is delayed" do
      it "still continues from the original target period" do
        travel_to(Time.zone.parse("2026-04-15")) do
          expect(result).to be_success
          expect(result.operation.target_cycle_started_at).to eq(target_end)
        end
      end
    end
  end

  context "when an arrears cycle has a price change" do
    let(:billing_timing) { "arrears" }
    let(:action_type) { "close_fixed_arrears" }
    let(:operation_current_at) { Time.zone.parse("2026-01-15") }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-15"),
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "continues to the later slice in the same cycle" do
      expect(result.operation).to have_attributes(
        billing_at: target_end,
        target_cycle_started_at: target_start
      )
    end
  end

  context "when the current cycle is terminal" do
    let(:contract) do
      create(:contract, organization:, customer:, started_at: target_start, ended_at: target_end)
    end

    it "does not create a successor" do
      expect(result).to be_success
      expect(result.operation).to be_nil
      expect(contract_rate_card.billing_operations.count).to eq(1)
    end
  end

  context "when the operation is cancelled" do
    before do
      operation.update!(cancelled_at: Time.zone.parse("2026-01-15"), cancelled_causation_type: :contract_termination)
    end

    it "does not create a continuation" do
      expect(result).to be_success
      expect(result.operation).to be_nil
      expect(contract_rate_card.billing_operations.count).to eq(1)
    end
  end

  context "when a processed successor already exists" do
    let!(:successor) do
      create(
        :billing_operation, organization:, contract_rate_card:,
        action_type: "renew_fixed_advance", causation_type: "periodic_continuation",
        billing_at: target_end, target_cycle_started_at: target_end
      )
    end

    it "creates another successor without deduplicating against it" do
      expect(result.operation).not_to eq(successor)
      expect(result.operation).to have_attributes(causation_type: "periodic_continuation", billing_at: target_end)
      expect(contract_rate_card.billing_operations.count).to eq(3)
    end
  end
end
