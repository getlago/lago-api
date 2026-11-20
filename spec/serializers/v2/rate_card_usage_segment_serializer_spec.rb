# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardUsageSegmentSerializer do
  subject(:payload) { described_class.new(segment).serialize }

  let(:segment) do
    RateCardUsageSegment.new(
      billing_segment: build_stubbed(
        :billing_segment,
        rate_card_rate: build_stubbed(:rate_card_rate, rate_model: "standard", rate_properties: {"amount" => "2"}),
        started_at: Time.zone.parse("2027-02-01T00:00:00Z"),
        ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-02-07T00:00:00Z"))
      ),
      fees: [
        build_stubbed(:fee, units: BigDecimal("2.5"), events_count: 3, amount_cents: 500),
        build_stubbed(:fee, units: BigDecimal(1), events_count: 1, amount_cents: 200)
      ]
    )
  end

  it "serializes the segment on its window, with its rate and its fees summed" do
    expect(payload).to eq(
      from_datetime: "2027-02-01T00:00:00Z",
      to_datetime: "2027-02-06T23:59:59Z",
      rate_model: "standard",
      rate_properties: {"amount" => "2"},
      units: "3.5", # 2.5 + 1
      events_count: 4,
      amount_cents: 700 # 500 + 200
    )
  end

  context "with the usec_timestamps include of a v2 render" do
    subject(:payload) { described_class.new(segment, includes: %i[usec_timestamps]).serialize }

    it "renders its window to the microsecond" do
      expect(payload.values_at(:from_datetime, :to_datetime)).to eq(%w[2027-02-01T00:00:00.000000Z 2027-02-06T23:59:59.999999Z])
    end
  end
end
