# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::ResetBillingClockService do
  subject(:result) { described_class.call(contract_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-09-30")) }
  let(:rate_card) { create(:rate_card, organization:) }
  # Seeded while the rate was monthly: the clock waits for the end of the first month.
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 9, 30),
      billing_anchor_date: Date.new(2026, 9, 30),
      next_billing_at: Time.zone.parse("2026-10-30")
    )
  end

  def complete_close(billing_at:, cycle_started_at:)
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_metered_arrears",
      billing_at:, target_cycle_started_at: cycle_started_at, coverage_started_at: cycle_started_at,
      coverage_ended_at: billing_at, processed_at: billing_at)
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-09-01"), billing_interval_unit: "week")
    create(:rate_phase, :contract_level, organization:, contract_rate_card:)
  end

  it "sets the clock to the first obligation when nothing was billed yet" do
    expect(result).to be_success
    expect(result.planned_operation).to have_attributes(
      cycle_started_at: Time.zone.parse("2026-09-30"), billing_at: Time.zone.parse("2026-10-07")
    )
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-07"))
  end

  context "with several pending operations" do
    before do
      [9, 8].each do |day|
        create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: Time.utc(2026, 10, day))
      end
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
        billing_at: Time.utc(2026, 10, 6))
    end

    it "projects the earliest due periodic date without returning a new plan" do
      result = described_class.call!(contract_rate_card:, timestamp: Time.utc(2026, 10, 9))
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 8))
    end

    it "uses the schedule when the pending periodic operations are still in the future" do
      result = described_class.call!(contract_rate_card:, timestamp: Time.utc(2026, 10, 7))
      expect(result.planned_operation.billing_at).to eq(Time.zone.parse("2026-10-07"))
    end
  end

  context "when the card has no schedule" do
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, next_billing_at: Time.zone.parse("2026-10-30")) }

    before { RateCardRate.where(rate_card:).delete_all }

    it "clears the clock" do
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "with a completed close" do
    before { complete_close(billing_at: Time.zone.parse("2026-10-07"), cycle_started_at: Time.zone.parse("2026-09-30")) }

    it "moves the clock to the next close" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.zone.parse("2026-10-07"), billing_at: Time.zone.parse("2026-10-14")
      )
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-14"))
    end

    it "reuses the card when planning after the completed close" do
      queries = []
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        planned = nil
        queries.concat(capture_sql { planned = original.call(**attributes) })
        planned
      end

      expect(result).to be_success
      expect(queries.grep(/FROM "contract_rate_cards"/)).to be_empty
    end

    context "when a new rate starts on the boundary of the close still owed" do
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-10-14"),
          billing_interval_unit: "week")
      end

      it "keeps the owed close rather than jumping to the cycle after the rate change" do
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-30"))
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-14"))
      end
    end

    context "when a later operation was cancelled" do
      before do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_metered_arrears",
          billing_at: Time.zone.parse("2026-10-14"), target_cycle_started_at: Time.zone.parse("2026-10-07"),
          cancelled_at: Time.zone.parse("2026-10-10"), cancellation_reason: :contract_termination)
      end

      it "plans from the last completed billing only" do
        expect(result.planned_operation.billing_at).to eq(Time.zone.parse("2026-10-14"))
      end
    end

    context "when a different action completed later" do
      before do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
          billing_at: Time.zone.parse("2026-10-14"), processed_at: Time.zone.parse("2026-10-14"))
      end

      it "continues from the completed operation for the current periodic action" do
        expect(result.planned_operation.billing_at).to eq(Time.zone.parse("2026-10-14"))
      end
    end
  end

  context "when a fixed advance rate changes after coverage was completed" do
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.utc(2026, 9, 30)) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance") }
    let(:billing_scope) { "segment" }
    let(:coverage_ended_at) { Time.utc(2026, 10, 7) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
        effective_date: Date.new(2026, 9, 30), billing_anchor_date: Date.new(2026, 9, 30))
    end

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
        billing_at: Time.utc(2026, 9, 30), target_cycle_started_at: Time.utc(2026, 9, 30),
        coverage_started_at: Time.utc(2026, 9, 30), coverage_ended_at:, processed_at: Time.utc(2026, 9, 30))
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 10, 3),
        billing_interval_unit: "week")
    end

    it "keeps the clock at the end of the completed coverage" do
      expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 10, 7))
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 7))
    end

    context "with cycle scope" do
      let(:billing_scope) { "cycle" }

      it "keeps the next cycle boundary" do
        expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 10, 7))
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 7))
      end
    end

    context "when only the first segment was covered" do
      let(:coverage_ended_at) { Time.utc(2026, 10, 3) }

      it "plans the next segment at the inclusive boundary" do
        expect(result.planned_operation.billing_at).to eq(Time.utc(2026, 10, 3))
      end
    end
  end

  context "when the schedule has run out" do
    let(:contract) do
      create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-09-30"),
        ended_at: Time.zone.parse("2026-10-20"))
    end

    before { complete_close(billing_at: Time.zone.parse("2026-10-20"), cycle_started_at: Time.zone.parse("2026-10-14")) }

    it "clears the clock, as no obligation is left" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end

    context "when termination follows the completed natural end" do
      let(:contract) do
        create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-09-30"),
          ended_at: Time.zone.parse("2026-10-20"), terminated_at: Time.zone.parse("2026-10-25"))
      end

      it "keeps the completed final close exhausted" do
        expect(result).to be_success
        expect(result.planned_operation).to be_nil
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end
    end
  end

  context "when paid fees are regrouped after service" do
    let(:billable_metric) do
      create(:billable_metric, organization:, aggregation_type: :sum_agg, recurring: false, field_name: "units")
    end
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing: "advance", regroup_paid_fees: "invoice", display_on_invoice: false)
    end

    it "updates the cursor to the service segment end" do
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-07"))
    end
  end

  context "when the card has no periodic action" do
    let(:billable_metric) do
      create(:billable_metric, organization:, aggregation_type: :sum_agg, recurring: false, field_name: "units")
    end
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: false) }

    it "clears the clock, as no obligation falls due" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end
end
