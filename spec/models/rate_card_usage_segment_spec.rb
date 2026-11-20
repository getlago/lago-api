# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardUsageSegment do
  subject(:segment) { described_class.new(billing_segment:, fees:) }

  let(:rate_override) { nil }
  let(:billing_segment) do
    build_stubbed(
      :billing_segment,
      rate_card_rate: build_stubbed(:rate_card_rate, rate_model: "standard", rate_properties: {"amount" => "2"}),
      rate_override:,
      started_at: Time.utc(2027, 2, 1),
      ended_at: BillingSegment.inclusive_end(Time.utc(2027, 2, 15))
    )
  end
  let(:fees) do
    [
      build_stubbed(:fee, units: BigDecimal("2.5"), events_count: 3, amount_cents: 250),
      build_stubbed(:fee, units: BigDecimal(1), events_count: nil, amount_cents: 100)
    ]
  end

  it "exposes its window and its rate, and sums its fees" do
    expect(segment).to have_attributes(
      started_at: Time.utc(2027, 2, 1), ended_at: BillingSegment.inclusive_end(Time.utc(2027, 2, 15)),
      rate_model: "standard", rate_properties: {"amount" => "2"},
      units: BigDecimal("3.5"), events_count: 3, amount_cents: 350
    )
  end

  context "without fees" do
    let(:fees) { [] }

    it "sums to zero, with decimal units" do
      expect(segment.units).to eq(BigDecimal(0))
      expect(segment.units).to be_a(BigDecimal)
      expect(segment).to have_attributes(events_count: 0, amount_cents: 0)
    end
  end

  context "when a phase override prices the segment" do
    let(:rate_override) { build_stubbed(:rate_override, rate_model: "package", rate_properties: {"amount" => "1"}) }

    it "exposes the override" do
      expect(segment).to have_attributes(rate_model: "package", rate_properties: {"amount" => "1"})
    end
  end
end
