# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule::DueOperationsService do
  subject(:result) { schedule_due }

  def schedule_due
    previous_operation = if contract_rate_card
      BillingOperation.latest_periodic_by_card([contract_rate_card], organization_id: organization.id, through: timestamp)[contract_rate_card.id]
    end
    described_class.call(contract_rate_card:, schedule:, timestamp:, previous_operation:)
  end

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
  let(:timestamp) { boundary }
  let(:anchor_at) { Time.utc(2026, 11, 1) }
  let(:anchor_cycle) { started_at }
  let(:anchor_action) { "close_fixed_arrears" }
  let(:anchor_processed_at) { nil }
  let(:anchor_coverage_end) { (billing_timing == "advance") ? anchor_at.advance(days: 1) : anchor_at }
  let(:anchor) do
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
      billing_at: anchor_at, target_cycle_started_at: anchor_cycle, processed_at: anchor_processed_at,
      coverage_ended_at: anchor_coverage_end)
  end
  let(:has_anchor) { true }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from,
      billing_interval_count: 1, billing_interval_unit: interval_unit)
    anchor if has_anchor
  end

  it "fills the daily gap through the cutoff without moving the clock" do
    expect { result }.not_to change { contract_rate_card.reload.next_billing_at }
    expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
    expect(anchor.reload).to have_attributes(billing_at: anchor_at, target_cycle_started_at: started_at)
    expect(result.billing_operations.map(&:reason).uniq).to eq(["periodic_continuation"])
  end

  context "when the anchor is completed" do
    let(:anchor_processed_at) { anchor_at }

    it "fills the gap without changing the completed operation" do
      expect { result }.not_to change { anchor.reload.attributes.slice("id", "billing_at", "target_cycle_started_at", "processed_at") }
      expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
      expect(anchor.reload).to have_attributes(
        billing_at: anchor_at, target_cycle_started_at: started_at, processed_at: anchor_processed_at
      )
    end
  end

  context "with advance billing" do
    let(:billing_timing) { "advance" }
    let(:anchor_action) { "renew_fixed_advance" }
    let(:anchor_cycle) { anchor_at }

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: started_at, target_cycle_started_at: started_at, processed_at: started_at,
        coverage_started_at: started_at, coverage_ended_at: anchor_at)
    end

    it "fills renewals through the cutoff" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
      expect(result.billing_operations.map(&:action_type).uniq).to eq(["renew_fixed_advance"])
    end
  end

  context "with gaps between pending advance renewals" do
    let(:billing_timing) { "advance" }
    let(:anchor_action) { "renew_fixed_advance" }
    let(:has_anchor) { false }
    let(:boundary) { Time.utc(2026, 11, 5) }
    let(:pending_dates) { [Time.utc(2026, 11, 2), Time.utc(2026, 11, 4)] }
    let(:pending_operations) do
      pending_dates.map do |date|
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
          billing_at: date, target_cycle_started_at: date, coverage_started_at: date, coverage_ended_at: date + 1.day)
      end
    end

    before { pending_operations }

    it "continues once from the latest pending coverage end" do
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: boundary, coverage_started_at: boundary, coverage_ended_at: boundary + 1.day
      )
      expect(schedule_due.raise_if_error!.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations.where(id: pending_operations.map(&:id)).count).to eq(2)
    end
  end

  context "with a customer timezone change at daylight saving" do
    let(:timezone) { "America/Los_Angeles" }
    let(:started_at) { Time.utc(2026, 10, 31, 7) }
    let(:anchor_at) { Time.utc(2026, 11, 1, 7) }
    let(:boundary) { Time.utc(2026, 11, 19, 8) }

    it "uses local daily boundaries" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it, 8) })
    end
  end

  context "without an earlier periodic operation" do
    let(:has_anchor) { false }

    it "starts with the first natural obligation" do
      expect(result.billing_operations.map(&:billing_at)).to eq((1..19).map { Time.utc(2026, 11, it) })
    end
  end

  context "with an earlier cutoff" do
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

    it "creates nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the schedule is missing" do
    let(:schedule) { nil }

    it "creates nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the card is missing" do
    let(:contract_rate_card) { nil }
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
        billing_at: boundary, target_cycle_started_at: Time.utc(2026, 11, 18), coverage_ended_at: boundary)
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 22), target_cycle_started_at: Time.utc(2026, 11, 21))
    end

    it "uses the current operation as the anchor without duplicating it" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations.where(billing_at: boundary).count).to eq(1)
    end
  end

  context "when another periodic close exists before the cutoff" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 10), target_cycle_started_at: Time.utc(2026, 11, 9),
        coverage_ended_at: Time.utc(2026, 11, 10))
    end

    it "starts after the latest prior operation" do
      expect(result.billing_operations.map(&:billing_at)).to eq((11..19).map { Time.utc(2026, 11, it) })
    end
  end

  context "when the later prior operation has a different action" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
        billing_at: Time.utc(2026, 11, 10), target_cycle_started_at: Time.utc(2026, 11, 10))
    end

    it "does not use it as an anchor" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
    end
  end

  context "when only cancelled or late-payment operations exist before the cutoff" do
    let(:has_anchor) { false }

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: Time.utc(2026, 11, 14), reason: :late_payment)
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: Time.utc(2026, 11, 16), target_cycle_started_at: Time.utc(2026, 11, 15),
        cancelled_at: Time.utc(2026, 11, 16), cancellation_reason: :rate_change)
    end

    it "does not use them as anchors" do
      expect(result.billing_operations.map(&:billing_at)).to eq((1..19).map { Time.utc(2026, 11, it) })
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
      expect(result.billing_operations.map(&:billing_at)).to eq((1..19).map { Time.utc(2026, 11, it) })
    end
  end

  context "when the same batch is requested twice" do
    it "is idempotent" do
      expect(result.billing_operations.size).to eq(18)
      expect(schedule_due.raise_if_error!.billing_operations).to be_empty
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

    it "creates both segment closes through the cycle close" do
      expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 11, 15), Time.utc(2026, 12, 1)])
    end

    context "when only the later fixed advance segment is pending" do
      let(:billing_timing) { "advance" }
      let(:anchor_action) { BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance) }
      let(:has_anchor) { true }
      let(:anchor_at) { Time.utc(2026, 11, 15) }
      let(:anchor_cycle) { started_at }
      let(:timestamp) { anchor_at }
      let(:anchor) do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
          billing_at: anchor_at, target_cycle_started_at: started_at, coverage_started_at: anchor_at, coverage_ended_at: boundary)
      end

      it "keeps the existing due renewal" do
        expect(result.billing_operations).to be_empty
        expect(contract_rate_card.billing_operations.sole).to eq(anchor)
        expect(anchor.reload).to have_attributes(coverage_started_at: anchor_at, coverage_ended_at: boundary)
      end

      context "when the later renewal is not yet due" do
        let(:timestamp) { anchor_at - 1.second }

        it "schedules the earlier segment once and preserves the later renewal" do
          earlier = result.billing_operations.sole
          expect(earlier).to have_attributes(
            action_type: anchor_action, coverage_started_at: started_at, coverage_ended_at: anchor_at
          )
          expect(schedule_due.raise_if_error!.billing_operations).to be_empty
          expect(contract_rate_card.billing_operations.pluck(:id)).to match_array([anchor.id, earlier.id])
        end
      end
    end

    context "when the first arrears segment was already closed" do
      let(:has_anchor) { true }
      let(:anchor_at) { Time.utc(2026, 11, 15) }
      let(:anchor_cycle) { started_at }
      let(:anchor_coverage_end) { anchor_at }
      let(:anchor_processed_at) { anchor_at }

      shared_examples "continues the uncovered arrears tail" do
        it "creates the remaining segment close" do
          expect(result.billing_operations.sole).to have_attributes(
            action_type: anchor_action, billing_at: boundary,
            coverage_started_at: anchor_at, coverage_ended_at: boundary
          )
        end
      end

      include_examples "continues the uncovered arrears tail"

      context "with metered arrears" do
        let(:product) { create(:product, organization:) }
        let(:anchor_action) { BillingOperation::ACTION_TYPES.fetch(:close_metered_arrears) }

        include_examples "continues the uncovered arrears tail"
      end
    end

    context "when fixed advance coverage was already completed" do
      let(:billing_timing) { "advance" }
      let(:anchor_action) { BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance) }
      let(:anchor_at) { started_at }
      let(:anchor_cycle) { started_at }
      let(:anchor_coverage_end) { boundary }
      let(:anchor_processed_at) { started_at }
      let(:has_anchor) { true }
      let(:reconciliation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage),
          reason: :rate_change, billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: started_at,
          coverage_started_at: Time.utc(2026, 11, 15), coverage_ended_at: boundary)
      end

      before { reconciliation }

      shared_examples "continues after completed coverage" do
        it "creates only the next renewal and remains idempotent" do
          expect(result.billing_operations.sole).to have_attributes(
            action_type: anchor_action, billing_at: boundary,
            coverage_started_at: boundary, coverage_ended_at: Time.utc(2027, 1, 1)
          )
          expect(schedule_due.raise_if_error!.billing_operations).to be_empty
          expect(contract_rate_card.billing_operations.reload.map(&:id)).to match_array(
            [anchor.id, reconciliation.id, result.billing_operations.sole.id]
          )
        end
      end

      include_examples "continues after completed coverage"

      context "with cycle billing" do
        let(:billing_scope) { "cycle" }

        include_examples "continues after completed coverage"
      end
    end

    context "when a new advance segment starts inside completed coverage" do
      let(:billing_timing) { "advance" }
      let(:anchor_action) { BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance) }
      let(:anchor_at) { started_at }
      let(:anchor_cycle) { started_at }
      let(:anchor_coverage_end) { Time.utc(2026, 11, 20) }
      let(:anchor_processed_at) { started_at }
      let(:has_anchor) { true }

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: anchor_coverage_end,
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "continues at the stored coverage end without reopening a priced slice" do
        expect(result.billing_operations.map { [it.coverage_started_at, it.coverage_ended_at] }).to eq([
          [Time.utc(2026, 11, 20), boundary], [boundary, Time.utc(2027, 1, 1)]
        ])
        expect(anchor.reload.coverage_ended_at).to eq(Time.utc(2026, 11, 20))
      end
    end

    context "when a pending close is after the cutoff" do
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

      it "creates only the cycle close" do
        expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 12, 1)])
      end
    end

    context "when termination follows the natural end" do
      let(:ended_at) { Time.utc(2026, 11, 20) }
      let(:terminated_at) { Time.utc(2026, 11, 25) }
      let(:contract) { create(:contract, :terminated, organization:, customer:, started_at:, ended_at:, terminated_at:) }
      let(:boundary) { terminated_at }

      it "fills the closes through termination" do
        expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 11, 15), terminated_at])
      end

      context "when the cutoff falls between the natural end and termination" do
        let(:timestamp) { Time.utc(2026, 11, 22) }

        it "applies the termination date before selecting due coverage" do
          expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 11, 15)])
        end
      end

      context "when the final close is the first natural obligation" do
        let(:ended_at) { Time.utc(2026, 11, 12) }
        let(:timestamp) { Time.utc(2026, 11, 22) }

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
