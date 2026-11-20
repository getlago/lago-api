# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardUsageSerializer do
  subject(:payload) { described_class.new(usage).serialize }

  let(:usage) { RateCardUsage.new(contract_rate_card:, obligation:, rate_phase:, segments: usage_segments) }
  let(:usage_segments) do
    segments.zip(segment_fees).map do |segment, fees|
      RateCardUsageSegment.new(
        billing_segment: build_stubbed(:billing_segment, contract_rate_card:, rate_card_rate: segment.rate, rate_override:,
          started_at: segment.started_at, ended_at: BillingSegment.inclusive_end(segment.ended_at)),
        fees:
      )
    end
  end
  let(:obligation) { Billing::Obligation.new(cycle:, segments:, billing_at: nil, terms: nil) }
  let(:cycle) { Billing::Cycle.new(index: 0, started_at: segments.first.started_at, ended_at: segments.last.ended_at, phase:, calendar: nil) }
  let(:phase) { Billing::Phase.new(code: nil, billing_interval_cycle_count: nil, rate_override:) }
  let(:billable_metric) { build_stubbed(:billable_metric, code: "api_calls") }
  let(:product_category) { build_stubbed(:product_category, code: "compute", name: "Compute") }
  let(:product) do
    build_stubbed(:product, billable_metric:, product_category:, code: "api", name: "API", invoice_display_name: "API usage")
  end
  let(:product_filter) { nil }
  let(:rate_card) { build_stubbed(:rate_card, product:, product_filter:, code: "api_monthly", name: "API monthly") }
  let(:contract_rate_card) { build_stubbed(:contract_rate_card, rate_card:) }
  let(:rate_override) { nil }
  let(:rate) { build_stubbed(:rate_card_rate, rate_card:, rate_properties: {"amount" => "2"}) }
  let(:segments) do
    [Billing::Segments::Segment.new(started_at: Time.zone.parse("2027-02-01T00:00:00Z"),
      ended_at: Time.zone.parse("2027-03-01T00:00:00Z"), rate:)]
  end
  let(:rate_phase) { nil }
  let(:segment_fees) do
    [[
      build_stubbed(:fee, units: BigDecimal("2.5"), events_count: 3, amount_cents: 500),
      build_stubbed(:fee, units: BigDecimal(1), events_count: 1, amount_cents: 200)
    ]]
  end
  let(:segment_payload) do
    {
      from_datetime: "2027-02-01T00:00:00Z",
      to_datetime: "2027-02-28T23:59:59Z",
      rate_model: "standard",
      rate_properties: {"amount" => "2"},
      units: "3.5",
      events_count: 4,
      amount_cents: 700
    }
  end
  let(:flat_payload) do
    {
      rate_card_code: "api_monthly",
      rate_card_name: "API monthly",
      product_code: "api",
      product_name: "API",
      product_category_code: "compute",
      product_category_name: "Compute",
      product_filter_code: nil,
      product_filter_name: nil,
      invoice_display_name: "API usage",
      product_type: "metered",
      billable_metric_code: "api_calls",
      billing_timing: "arrears",
      from_datetime: "2027-02-01T00:00:00Z",
      to_datetime: "2027-02-28T23:59:59Z",
      rate_phase_code: nil,
      rate_phase_name: nil,
      rate_source: "rate",
      units: "3.5",
      events_count: 4,
      amount_cents: 700,
      segments: [segment_payload]
    }
  end

  it "serializes the card on its window, with its fees summed" do
    expect(payload).to eq(flat_payload)
  end

  context "with multiple priced segments" do
    let(:segments) do
      [
        Billing::Segments::Segment.new(started_at: Time.zone.parse("2027-02-01"),
          ended_at: Time.zone.parse("2027-02-07"), rate:),
        Billing::Segments::Segment.new(started_at: Time.zone.parse("2027-02-07"),
          ended_at: Time.zone.parse("2027-03-01"),
          rate: build_stubbed(:rate_card_rate, rate_card:, rate_model: "package", rate_properties: {"amount" => "5"}))
      ]
    end

    let(:segment_fees) do
      [
        [build_stubbed(:fee, units: BigDecimal("2.5"), events_count: 3, amount_cents: 500)],
        [build_stubbed(:fee, units: BigDecimal(1), events_count: 1, amount_cents: 200)]
      ]
    end

    it "renders the whole window, and each segment with its own rate and usage" do
      expect(payload).to eq(
        flat_payload.merge(
          segments: [
            {from_datetime: "2027-02-01T00:00:00Z", to_datetime: "2027-02-06T23:59:59Z", rate_model: "standard",
             rate_properties: {"amount" => "2"}, units: "2.5", events_count: 3, amount_cents: 500},
            {from_datetime: "2027-02-07T00:00:00Z", to_datetime: "2027-02-28T23:59:59Z", rate_model: "package",
             rate_properties: {"amount" => "5"}, units: "1.0", events_count: 1, amount_cents: 200}
          ]
        )
      )
    end
  end

  context "with a product filter" do
    let(:product_filter) do
      build_stubbed(:product_filter, product:, code: "eu", name: "Europe", invoice_display_name: "API usage, Europe")
    end

    it "renders the filter and its invoice name" do
      expect(payload).to eq(
        flat_payload.merge(product_filter_code: "eu", product_filter_name: "Europe", invoice_display_name: "API usage, Europe")
      )
    end
  end

  context "with a phase override" do
    let(:rate_override) { build_stubbed(:rate_override, rate_model: "package", rate_properties: {"amount" => "2"}) }
    let(:rate_phase) { build_stubbed(:rate_phase, :contract_level, contract_rate_card:, code: "intro", name: "Intro") }

    it "renders the phase, and the rate model of its override on the segment" do
      expect(payload).to eq(
        flat_payload.merge(rate_phase_code: "intro", rate_phase_name: "Intro", rate_source: "phase_override",
          segments: [segment_payload.merge(rate_model: "package")])
      )
    end
  end

  context "with a fixed product outside any category" do
    let(:product) { build_stubbed(:product, :fixed, :standalone, code: "seats", name: "Seats", invoice_display_name: nil) }

    it "renders null category and metric codes, and the product name on invoices" do
      expect(payload).to eq(
        flat_payload.merge(
          product_code: "seats",
          product_name: "Seats",
          product_category_code: nil,
          product_category_name: nil,
          invoice_display_name: "Seats",
          product_type: "fixed",
          billable_metric_code: nil
        )
      )
    end
  end
end
