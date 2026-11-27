# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ResolveSegmentsService do
  subject(:result) { described_class.call(operation: operation.reload) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
      rate_model: "standard", rate_properties: {"amount" => "10"})
  end
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1), units: 1)
  end
  let(:operation) do
    rate
    schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
    planned_operation = BillingOperations::Schedule::PlannedOperation.from_obligation(schedule.obligation_at(Time.utc(2026, 1, 1)))
    BillingOperations::CreateService.call!(
      contract_rate_card:, action_type: "renew_fixed_advance", reason: :contract_activation, planned_operation:
    ).operation
  end

  it "keeps saved coverage and the rate reference while using that rate's current properties" do
    operation
    rate.update!(rate_properties: {"amount" => "50"})
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
      rate_model: "standard", rate_properties: {"amount" => "20"})

    expect(result).to be_success
    expect(result.billing_segments.size).to eq(1)
    expect(result.billing_segments.sole).to have_attributes(
      started_at: Time.utc(2026, 1, 1), ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1)),
      rate_card_rate_id: rate.id, rate_properties: {"amount" => "50"}, billing_at: Time.utc(2026, 1, 1)
    )
    expect(operation.reload).to have_attributes(
      coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 2, 1)
    )
  end

  context "with a saved phase override" do
    let(:override) { create(:rate_override, organization:, rate_properties: {"amount" => "17"}) }
    let(:override_phase) { create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override) }

    before do
      override_phase
      operation
      override_phase.update!(rate_override: nil)
    end

    it "prices from the saved override after the phase changes" do
      expect(result.billing_segments.sole).to have_attributes(rate_card_rate: rate, rate_override: override,
        rate_properties: {"amount" => "17"})
    end
  end

  context "when a periodic operation has no saved segments" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
        target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    it "returns an empty list even when the catalog has a rate" do
      rate
      expect(result).to be_success
      expect(result.billing_segments).to eq([])
    end
  end

  context "when resolving a rate-change reconciliation" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "reconcile_advance_coverage", reason: "rate_change",
        billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    it "returns no segments when none were saved" do
      expect(result).to be_success
      expect(result.billing_segments).to be_empty
    end

    context "with two saved segments" do
      let(:start_at) { Time.utc(2026, 1, 1) }
      let(:boundary) { Time.utc(2026, 1, 15) }
      let(:end_at) { Time.utc(2026, 2, 1) }

      before do
        operation.segments.create!(organization:, position: 1, rate_card_rate: rate, started_at: boundary, ended_at: end_at, proration_ratio: 17.to_d / 31)
        operation.segments.create!(organization:, position: 0, rate_card_rate: rate, started_at: start_at, ended_at: boundary, proration_ratio: 14.to_d / 31)
      end

      it "returns both windows in position order and leaves the reconciliation pending" do
        expect { result }.not_to change(Invoice, :count)
        expect(result).to be_success
        expect(result.billing_segments.map { [it.started_at, it.ended_at] }).to eq([
          [start_at, BillingSegment.inclusive_end(boundary)], [boundary, BillingSegment.inclusive_end(end_at)]
        ])
        expect(operation.reload).to have_attributes(invoice_id: nil, processed_at: nil, cancelled_at: nil)
      end
    end
  end
end
