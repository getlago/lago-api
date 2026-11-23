# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule::BuildPlannedOperation do
  subject(:result) do
    described_class.call(schedule:, **planning)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:billing_timing) { "advance" }
  let(:billing_scope) { "cycle" }
  let(:contract_rate_card) do
    create(
      :contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1)
    )
  end
  let(:schedule) { Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule }
  let(:timestamp) { Time.utc(2026, 11, 1) }
  let(:after) { nil }
  let(:target_cycle_started_at) { Time.utc(2026, 11, 1, 7) }
  let(:coverage_ended_at) { Time.utc(2026, 12, 1, 8) }
  let(:after_operation) do
    build_stubbed(:billing_operation, organization:, customer:, contract_rate_card:,
      billing_at: after, target_cycle_started_at:, coverage_started_at: target_cycle_started_at, coverage_ended_at:)
  end
  let(:planning) { after ? {after_operation:} : {at: timestamp} }
  let(:rate_effective_from) { Time.utc(2026, 11, 1) }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from, billing_interval_count: 1, billing_interval_unit: "month")
  end

  it "returns the first planned obligation using the customer's timezone" do
    expect(result).to be_success
    expect(result.planned_operation).to have_attributes(
      cycle_started_at: Time.utc(2026, 11, 1, 7),
      billing_at: Time.utc(2026, 11, 1, 7)
    )
    expect(result.planned_operation).to be_a(BillingOperations::Schedule::PlannedOperation)
  end

  context "when billing in arrears" do
    let(:billing_timing) { "arrears" }

    it "plans billing at the end of the segment" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when a rate changes at a mid-cycle billing boundary" do
    let(:billing_scope) { "segment" }
    let(:timestamp) { Time.utc(2026, 11, 15) }
    let(:rate_effective_from) { Time.utc(2026, 11, 1) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp,
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    context "when billing in arrears" do
      let(:billing_timing) { "arrears" }

      it "selects the segment opening at the boundary" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 11, 1, 7),
          billing_at: Time.utc(2026, 12, 1, 8)
        )
      end

      context "when the scope covers the cycle" do
        let(:billing_scope) { "cycle" }

        it "waits until the cycle closes" do
          expect(result.planned_operation).to have_attributes(
            cycle_started_at: target_cycle_started_at, billing_at: Time.utc(2026, 12, 1, 8)
          )
        end
      end
    end

    context "when billing in advance" do
      it "selects the new segment opening at the boundary" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 11, 1, 7),
          billing_at: timestamp
        )
      end

      context "when the scope covers the cycle" do
        let(:billing_scope) { "cycle" }

        it "keeps the opening obligation instead of creating a rate-change obligation" do
          expect(result.planned_operation).to have_attributes(
            cycle_started_at: target_cycle_started_at, billing_at: target_cycle_started_at
          )
        end
      end
    end

    context "when regrouping paid fees" do
      let(:product) { create(:product, organization:) }
      let(:rate_card) do
        create(:rate_card, organization:, product:, billing_timing:, regroup_paid_fees: :invoice, display_on_invoice: false)
      end

      it "selects the segment opening at the boundary" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 11, 1, 7),
          billing_at: Time.utc(2026, 12, 1, 8)
        )
      end

      context "when the scope covers the cycle" do
        let(:billing_scope) { "cycle" }

        it "regroups at the cycle close rather than the rate change" do
          expect(result.planned_operation).to have_attributes(
            cycle_started_at: target_cycle_started_at, billing_at: Time.utc(2026, 12, 1, 8)
          )
        end
      end
    end

    context "when selecting after the boundary was completed" do
      let(:billing_timing) { "arrears" }
      let(:after) { timestamp }
      let(:coverage_ended_at) { timestamp }

      it "skips the boundary and selects the next closing segment" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 11, 1, 7),
          billing_at: Time.utc(2026, 12, 1, 8)
        )
      end
    end
  end

  context "when regrouping paid fees" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing:, regroup_paid_fees: :invoice, display_on_invoice: false)
    end

    it "plans billing at the end of service" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end

    context "when selecting after a completed segment" do
      let(:billing_scope) { "segment" }
      let(:timestamp) { Time.utc(2026, 11, 1, 7) }
      let(:after) { Time.utc(2026, 11, 15) }
      let(:coverage_ended_at) { Time.utc(2026, 11, 15) }

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "plans the next uncovered segment's close" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 11, 1, 7),
          billing_at: Time.utc(2026, 12, 1, 8)
        )
      end
    end
  end

  context "when the timestamp is at the first segment boundary" do
    let(:timestamp) { Time.utc(2026, 12, 1, 8) }

    it "selects the next segment rather than reopening completed coverage" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 12, 1, 8),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when selecting after completed segment coverage" do
    let(:billing_scope) { "segment" }
    let(:timestamp) { Time.utc(2026, 11, 1, 7) }
    let(:after) { Time.utc(2026, 11, 1, 7) }
    let(:coverage_ended_at) { Time.utc(2026, 11, 15) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "skips completed coverage within the same cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 11, 15)
      )
    end

    context "when the scope covers the cycle" do
      let(:billing_scope) { "cycle" }
      let(:coverage_ended_at) { Time.utc(2026, 12, 1, 8) }

      it "advances to the next cycle without billing again at the rate change" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2026, 12, 1, 8)
        )
      end
    end
  end

  context "with stored coverage on a previous operation" do
    let(:billing_scope) { "segment" }
    let(:after) { target_cycle_started_at }
    let(:coverage_ended_at) { Time.utc(2026, 12, 1, 8) }
    let(:action_type) { "renew_fixed_advance" }
    let(:after_operation) do
      build_stubbed(:billing_operation, organization:, customer:, contract_rate_card:, action_type:,
        billing_at: after, target_cycle_started_at:, coverage_started_at: target_cycle_started_at, coverage_ended_at:)
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15),
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "does not reopen previously covered time and includes the next boundary" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2026, 12, 1, 8)
      )
    end

    context "when the previous segment ended at the rate change" do
      let(:coverage_ended_at) { Time.utc(2026, 11, 15) }

      it "plans the segment beginning at that boundary" do
        expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 11, 15))
      end
    end

    context "when stored coverage ends within a newly inserted segment" do
      let(:coverage_ended_at) { Time.utc(2026, 11, 20) }

      it "skips the overlapping segment instead of reopening it" do
        expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 12, 1, 8))
      end
    end

    context "when the next coverage boundary is also the previous billing instant" do
      let(:after) { Time.utc(2026, 12, 1, 8) }

      it "does not skip unowned coverage because its billing date matches" do
        expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 12, 1, 8))
      end
    end

    context "when billing was late, after the next coverage began" do
      let(:coverage_ended_at) { Time.utc(2026, 11, 15) }
      let(:after) { Time.utc(2026, 11, 20) }

      it "does not skip the next unowned segment" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: Time.utc(2026, 11, 15), billing_at: Time.utc(2026, 11, 15)
        )
      end
    end

    context "when the scope covers the cycle" do
      let(:billing_scope) { "cycle" }

      it "continues at the next cycle" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2026, 12, 1, 8)
        )
      end
    end

    context "when the previous operation is an arrears close" do
      let(:action_type) { "close_fixed_arrears" }
      let(:billing_timing) { "arrears" }
      let(:after) { Time.utc(2026, 11, 15) }

      it "skips segments within the stored coverage" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2027, 1, 1, 8)
        )
      end

      context "when only the first segment was covered" do
        let(:coverage_ended_at) { Time.utc(2026, 11, 15) }

        it "includes the next segment even though billing is at its end" do
          expect(result.planned_operation).to have_attributes(
            coverage_started_at: Time.utc(2026, 11, 15), billing_at: Time.utc(2026, 12, 1, 8)
          )
        end
      end

      context "when metered in arrears" do
        let(:product) { create(:product, organization:) }
        let(:action_type) { "close_metered_arrears" }

        it "respects the stored end" do
          expect(result.planned_operation).to have_attributes(
            coverage_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2027, 1, 1, 8)
          )
        end
      end
    end

    context "when regrouping paid metered fees" do
      let(:product) { create(:product, organization:) }
      let(:rate_card) do
        create(:rate_card, organization:, product:, billing_timing:, regroup_paid_fees: :invoice, display_on_invoice: false)
      end
      let(:action_type) { "regroup_paid_fees" }
      let(:after) { Time.utc(2026, 11, 15) }

      it "respects the coverage end independently of the close date" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2027, 1, 1, 8)
        )
      end
    end

    context "when renewing recurring metered usage in advance" do
      let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
      let(:product) { create(:product, organization:, billable_metric:) }
      let(:action_type) { "renew_recurring_metered_advance" }

      it "respects the stored end" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: Time.utc(2026, 12, 1, 8), billing_at: Time.utc(2026, 12, 1, 8)
        )
      end
    end

    context "when planning after a reconciliation operation" do
      let(:action_type) { "reconcile_advance_coverage" }

      it "uses the same coverage boundary" do
        expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 12, 1, 8))
      end
    end
  end

  context "when the completed billing instant is the cycle's first advance date" do
    let(:timestamp) { Time.utc(2026, 11, 1, 7) }
    let(:after) { Time.utc(2026, 11, 1, 7) }

    it "returns the next cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 12, 1, 8),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when billing in arrears after a completed mid-cycle segment" do
    let(:billing_scope) { "segment" }
    let(:billing_timing) { "arrears" }
    let(:timestamp) { Time.utc(2026, 11, 1, 7) }
    let(:after) { Time.utc(2026, 11, 15) }
    let(:coverage_ended_at) { Time.utc(2026, 11, 15) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "returns the next segment in the same cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when termination follows the planned end" do
    let(:billing_timing) { "arrears" }
    let(:timestamp) { Time.utc(2026, 11, 1, 7) }
    let(:ended_at) { Time.utc(2026, 11, 10, 8) }
    let(:terminated_at) { Time.utc(2026, 11, 15) }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: timestamp, ended_at:, terminated_at:)
    end
    let(:after) { Time.utc(2026, 11, 5) }
    let(:coverage_ended_at) { Time.utc(2026, 11, 5) }
    let(:billing_scope) { "segment" }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 5),
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    context "when the final coverage is one microsecond long" do
      let(:ended_at) { Time.utc(2026, 11, 5) + Rational(1, 1_000_000) }
      let(:planning) { {at: BillingSegment.inclusive_end(ended_at)} }

      it "selects the final segment rather than the segment closing at the cut" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: Time.utc(2026, 11, 5), coverage_ended_at: ended_at
        )
      end
    end

    it "plans the outstanding final close at termination" do
      expect(result.planned_operation).to have_attributes(cycle_started_at: timestamp, billing_at: terminated_at)
    end

    context "with stored coverage ending at a segment boundary" do
      let(:billing_scope) { "segment" }
      let(:after_operation) do
        build_stubbed(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
          billing_at: after, target_cycle_started_at: timestamp, coverage_started_at: timestamp, coverage_ended_at: after)
      end

      it "projects the remaining segment's billing to termination" do
        expect(result.planned_operation).to have_attributes(
          coverage_started_at: after, coverage_ended_at: ended_at, billing_at: terminated_at
        )
      end
    end

    context "when the close at the planned end was completed" do
      let(:after) { ended_at }
      let(:coverage_ended_at) { ended_at }

      it "does not reopen the completed coverage at termination" do
        expect(result).to be_success
        expect(result.planned_operation).to be_nil
      end
    end

    context "when the close at termination was completed" do
      let(:after) { terminated_at }
      let(:coverage_ended_at) { ended_at }

      it "returns no further obligation" do
        expect(result.planned_operation).to be_nil
      end
    end
  end

  context "when the first price starts after the current cycle" do
    let(:rate_effective_from) { Time.utc(2026, 12, 15) }

    it "plans the first priced segment of the next billable cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 12, 1, 8),
        billing_at: Time.utc(2026, 12, 15)
      )
    end
  end

  context "with an exhausted schedule" do
    let(:schedule) { instance_double(Billing::RateCards::Schedule, obligation_at: nil, next_obligation: nil) }

    it "returns no planned operation" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
    end
  end

  context "when neither or both planning instants are given" do
    it "refuses the call" do
      expect { described_class.call(schedule:) }.to raise_error(ArgumentError, /either at: or after_operation:/)
      expect { described_class.call(schedule:, at: timestamp, after_operation:) }
        .to raise_error(ArgumentError, /either at: or after_operation:/)
    end
  end
end
