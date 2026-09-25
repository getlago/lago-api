# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::CreateService do
  subject(:result) { described_class.call(contract_rate_card:, billable_segments: [billable_segment], pricing_unit:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "12"}) }
  let(:rate_override) { nil }
  let(:pricing_unit) { nil }

  let(:cycle_started_at) { Time.zone.parse("2026-02-01 00:00:00") }
  let(:exclusive_end) { Time.zone.parse("2026-03-01 00:00:00") }
  let(:calendar) do
    Billing::Calendar.new(anchor_date: cycle_started_at.to_date,
      interval: Billing::Interval.new(count: 1, unit: :month), timezone: "UTC")
  end
  let(:cycle) do
    Billing::Cycle.new(index: 0, started_at: cycle_started_at, ended_at: exclusive_end,
      phase: Billing::Phase.default, calendar:)
  end

  let(:billable_segment) do
    Billing::BillableSegment.new(
      cycle:,
      started_at: Time.zone.parse("2026-02-15 00:00:00"),
      ended_at: exclusive_end,
      billing_at: exclusive_end,
      rate:,
      rate_override:,
      proration_ratio: 0.5
    )
  end

  describe "#call" do
    it "links the slice to its full calendar cycle" do
      expect(result.billing_segments.sole.billing_cycle).to have_attributes(
        contract_rate_card_id: contract_rate_card.id,
        started_at: cycle_started_at,
        reference_started_at: cycle_started_at,
        ended_at: exclusive_end,
        cycle_index: 0,
        timezone: "UTC"
      )
    end

    it "stores a metered arrears slice as a pending segment" do
      expect(result.billing_segments.sole).to have_attributes(
        organization_id: organization.id,
        contract_id: contract.id,
        customer_id: customer.id,
        contract_rate_card_id: contract_rate_card.id,
        cycle_started_at:,
        started_at: Time.zone.parse("2026-02-15 00:00:00"),
        billing_at: exclusive_end,
        rate_card_rate_id: rate.id,
        rate_override_id: nil,
        rate_properties: {"amount" => "12"},
        currency: "USD",
        pricing_unit_id: nil,
        proration_ratio: 0.5,
        status: "pending"
      )
    end

    context "with a metered advance rate card" do
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }

      it "stores the slice as a processing segment" do
        expect(result.billing_segments.sole.status).to eq("processing")
      end
    end

    context "with a fixed advance rate card" do
      let(:product) { create(:product, :fixed, organization:) }
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }

      it "stores the slice as a pending segment" do
        expect(result.billing_segments.sole.status).to eq("pending")
      end
    end

    context "with a fixed arrears rate card" do
      let(:product) { create(:product, :fixed, organization:) }

      it "stores the slice as a pending segment" do
        expect(result.billing_segments.sole.status).to eq("pending")
      end
    end

    # A neighbour in the same organization: every owner on the row is derived from the card,
    # so a spec with one customer of one contract cannot tell a right derivation from a lucky one.
    it "takes its owners from the card's own contract, not from a sibling" do
      other_customer = create(:customer, organization:)
      create(:contract, organization:, customer: other_customer)

      expect(result.billing_segments.sole).to have_attributes(
        customer_id: customer.id,
        contract_id: contract.id
      )
    end

    it "converts the calendar's exclusive end to the stored inclusive end" do
      expect(result.billing_segments.sole.ended_at).to eq(exclusive_end - BillingSegment::MICROSECOND)
    end

    context "when the rate card prices in a pricing unit" do
      let(:pricing_unit) { create(:pricing_unit, organization:) }

      it "stores the unit the caller resolved" do
        expect(result.billing_segments.sole.pricing_unit_id).to eq(pricing_unit.id)
      end
    end

    context "when a phase override prices the slice" do
      let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "7"}) }

      it "snapshots the override's properties over the rate's" do
        expect(result.billing_segments.sole).to have_attributes(
          rate_card_rate_id: rate.id,
          rate_override_id: rate_override.id,
          rate_properties: {"amount" => "7"}
        )
      end
    end
  end
end
