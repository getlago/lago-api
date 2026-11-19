# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule::DueOperationsService do
  subject(:result) { described_class.call(contract_rate_card:, next_planned_operation:, schedule:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:started_at) { Time.utc(2026, 10, 31) }
  let(:contract) { create(:contract, organization:, customer:, started_at:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:billing_scope) { "cycle" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:interval_unit) { "day" }
  let(:rate_effective_from) { started_at }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2026, 10, 31), billing_anchor_date: Date.new(2026, 10, 31))
  end
  let(:schedule) { Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule }
  let(:boundary) { Time.utc(2026, 11, 19) }
  let(:planning_at) { (billing_timing == "advance") ? boundary : boundary - 1.second }
  let(:next_planned_operation) { BillingOperations::Schedule::BuildPlannedOperation.call!(schedule:, at: planning_at).planned_operation }
  let(:timestamp) { boundary }
  let(:anchor_at) { Time.utc(2026, 11, 1) }
  let(:anchor_cycle) { started_at }
  let(:anchor_action) { "close_fixed_arrears" }
  let(:anchor_processed_at) { nil }
  let(:anchor) do
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
      billing_at: anchor_at, target_cycle_started_at: anchor_cycle, processed_at: anchor_processed_at)
  end
  let(:has_anchor) { true }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from,
      billing_interval_count: 1, billing_interval_unit: interval_unit)
    anchor if has_anchor
  end

  it "fills the daily gap before the supplied plan without moving the clock" do
    expect(next_planned_operation).to have_attributes(cycle_started_at: Time.utc(2026, 11, 18), billing_at: boundary)
    expect { result }.not_to change { contract_rate_card.reload.next_billing_at }
    expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it) })
    expect(anchor.reload).to have_attributes(billing_at: anchor_at, target_cycle_started_at: started_at)
    expect(contract_rate_card.billing_operations.where(billing_at: boundary)).to be_empty
    expect(result.billing_operations.map(&:reason).uniq).to eq(["periodic_continuation"])
  end

  context "when the anchor is completed" do
    let(:anchor_processed_at) { anchor_at }

    it "fills the gap without changing the completed operation or creating the supplied plan" do
      expect { result }.not_to change { anchor.reload.attributes.slice("id", "billing_at", "target_cycle_started_at", "processed_at") }
      expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it) })
      expect(anchor.reload).to have_attributes(
        billing_at: anchor_at, target_cycle_started_at: started_at, processed_at: anchor_processed_at
      )
      expect(contract_rate_card.billing_operations.where(billing_at: boundary)).to be_empty
    end
  end

  context "when the cutoff is later than the supplied plan" do
    let(:timestamp) { Time.utc(2026, 11, 25) }
    let(:selected_obligations) { [] }

    before do
      allow(schedule).to receive(:obligations_due_by).and_wrap_original do |original, *args, **kwargs, &block|
        original.call(*args, **kwargs, &block).tap { selected_obligations.concat(it) }
      end
    end

    it "bounds calendar selection at the plan and persists only earlier obligations" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it) })
      expect(selected_obligations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
      expect(contract_rate_card.billing_operations.where(billing_at: boundary..).count).to eq(0)
    end
  end

  context "with advance billing" do
    let(:billing_timing) { "advance" }
    let(:anchor_action) { "renew_fixed_advance" }
    let(:anchor_cycle) { anchor_at }

    it "fills renewals before the supplied plan" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it) })
      expect(result.billing_operations.map(&:action_type).uniq).to eq(["renew_fixed_advance"])
    end
  end

  context "with a customer timezone change at daylight saving" do
    let(:timezone) { "America/Los_Angeles" }
    let(:started_at) { Time.utc(2026, 10, 31, 7) }
    let(:anchor_at) { Time.utc(2026, 11, 1, 7) }
    let(:boundary) { Time.utc(2026, 11, 19, 8) }

    it "uses local daily boundaries" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it, 8) })
    end
  end

  context "without an earlier periodic operation" do
    let(:has_anchor) { false }

    it "starts with the first natural obligation" do
      expect(result.billing_operations.map(&:billing_at)).to eq((1..18).map { Time.utc(2026, 11, it) })
    end

    it "looks up the previous operation only once when none exists" do
      queries = capture_sql { result }

      expect(queries.grep(/SELECT .*FROM "billing_operations"/).size).to eq(1)
    end
  end

  context "when the cutoff precedes the plan" do
    let(:timestamp) { Time.utc(2026, 11, 5) }

    it "includes the cutoff but not later obligations" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..5).map { Time.utc(2026, 11, it) })
    end
  end

  context "when the cutoff precedes the first missing close" do
    let(:timestamp) { Time.utc(2026, 11, 1) }

    it "creates nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the first price starts after the cutoff" do
    let(:has_anchor) { false }
    let(:rate_effective_from) { Time.utc(2026, 11, 10) }
    let(:timestamp) { Time.utc(2026, 11, 5) }
    let(:next_planned_operation) { nil }

    it "creates nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when there is no future plan" do
    let(:next_planned_operation) { nil }

    it "fills all obligations through the cutoff" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
    end
  end

  context "when the schedule is missing" do
    let(:schedule) { nil }
    let(:next_planned_operation) { nil }

    it "creates nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the card is missing" do
    let(:contract_rate_card) { nil }
    let(:next_planned_operation) { nil }
    let(:schedule) { nil }
    let(:has_anchor) { false }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the card has no periodic action" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: false) }
    let(:has_anchor) { false }

    it "creates nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when current and future operations already exist" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: boundary, target_cycle_started_at: Time.utc(2026, 11, 18))
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 22), target_cycle_started_at: Time.utc(2026, 11, 21))
    end

    it "ignores them as anchors and does not duplicate them" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it) })
      expect(contract_rate_card.billing_operations.where(billing_at: boundary).count).to eq(1)
    end
  end

  context "when another periodic close exists before the plan" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 10), target_cycle_started_at: Time.utc(2026, 11, 9))
    end

    it "starts after the latest prior operation" do
      expect(result.billing_operations.map(&:billing_at)).to eq((11..18).map { Time.utc(2026, 11, it) })
    end
  end

  context "when the later prior operation has a different action" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
        billing_at: Time.utc(2026, 11, 10), target_cycle_started_at: Time.utc(2026, 11, 10))
    end

    it "does not use it as an anchor" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..18).map { Time.utc(2026, 11, it) })
    end
  end

  context "when only cancelled or late-payment operations exist before the plan" do
    let(:has_anchor) { false }

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: Time.utc(2026, 11, 14), reason: :late_payment)
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 16), target_cycle_started_at: Time.utc(2026, 11, 15),
        cancelled_at: Time.utc(2026, 11, 16), cancellation_reason: :rate_change)
    end

    it "does not use them as anchors" do
      expect(result.billing_operations.map(&:billing_at)).to eq((1..18).map { Time.utc(2026, 11, it) })
    end
  end

  context "with another customer's operation" do
    let(:has_anchor) { false }
    let(:other_customer) { create(:customer, organization:) }
    let(:other_contract) { create(:contract, organization:, customer: other_customer) }
    let(:other_card) { create(:contract_rate_card, organization:, contract: other_contract) }

    before do
      create(:billing_operation, organization:, contract_rate_card: other_card, customer: other_customer,
        action_type: anchor_action, billing_at: Time.utc(2026, 11, 18), target_cycle_started_at: Time.utc(2026, 11, 17))
    end

    it "does not use it as an anchor" do
      expect(result.billing_operations.map(&:billing_at)).to eq((1..18).map { Time.utc(2026, 11, it) })
    end
  end

  context "when the same batch is requested twice" do
    it "is idempotent" do
      expect(result.billing_operations.size).to eq(17)
      expect(described_class.call!(contract_rate_card:, next_planned_operation:, schedule:, timestamp:).billing_operations).to be_empty
    end
  end

  context "with a mid-cycle rate change" do
    let(:started_at) { Time.utc(2026, 11, 1) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
        effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1))
    end
    let(:interval_unit) { "month" }
    let(:billing_scope) { "segment" }
    let(:has_anchor) { false }
    let(:boundary) { Time.utc(2026, 12, 1) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15),
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "backfills the segment close before the cycle close" do
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: started_at
      )
    end

    context "when a pending close is after the cutoff but before the next plan" do
      let(:timestamp) { Time.utc(2026, 11, 15) }

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
          billing_at: Time.utc(2026, 11, 20), target_cycle_started_at: started_at)
      end

      it "does not let the future operation hide the due segment" do
        expect(result.billing_operations.sole.billing_at).to eq(timestamp)
      end
    end

    context "when billing by cycle" do
      let(:billing_scope) { "cycle" }

      it "does not invent a segment obligation" do
        expect(result.billing_operations).to be_empty
      end
    end

    context "when termination follows the natural end" do
      let(:ended_at) { Time.utc(2026, 11, 20) }
      let(:terminated_at) { Time.utc(2026, 11, 25) }
      let(:contract) { create(:contract, :terminated, organization:, customer:, started_at:, ended_at:, terminated_at:) }
      let(:boundary) { terminated_at }
      let(:previous) do
        build(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
          billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: started_at)
      end
      let(:next_planned_operation) do
        BillingOperations::Schedule::BuildPlannedOperation.call!(schedule:, after_operation: previous).planned_operation
      end

      it "backfills the earlier close and excludes the final termination close" do
        expect(next_planned_operation.billing_at).to eq(terminated_at)
        expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 11, 15)])
      end

      context "when there is no future plan" do
        let(:next_planned_operation) { nil }

        it "fills the final close through termination" do
          expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 11, 15), terminated_at])
        end
      end

      context "when the cutoff falls between the natural end and termination" do
        let(:timestamp) { Time.utc(2026, 11, 22) }
        let(:next_planned_operation) { super().with(billing_at: terminated_at + 1.day) }

        it "applies the termination date before selecting due coverage" do
          expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 11, 15)])
        end
      end

      context "when the final close is the first natural obligation" do
        let(:ended_at) { Time.utc(2026, 11, 12) }
        let(:timestamp) { Time.utc(2026, 11, 22) }
        let(:next_planned_operation) do
          BillingOperations::Schedule::BuildPlannedOperation.call!(schedule:, at: started_at)
            .planned_operation.with(billing_at: terminated_at + 1.day)
        end

        it "keeps the first natural close before the cutoff" do
          expect(result.billing_operations.map(&:billing_at)).to eq([ended_at])
        end
      end
    end
  end

  context "when a later creation fails" do
    let(:calls) { [] }
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      allow(BillingOperations::CreateService).to receive(:call!).and_wrap_original do |original, **attributes|
        calls << attributes
        raise BaseService::FailedResult.new(failure, "cannot schedule") if calls.size == 2

        original.call(**attributes)
      end
    end

    it "rolls back the batch even inside an outer transaction" do
      ApplicationRecord.transaction do
        expect(result).to be_failure
        expect(result.billing_operations).to be_empty
        expect(contract_rate_card.billing_operations.reload).to eq([anchor])
      end
    end
  end
end
