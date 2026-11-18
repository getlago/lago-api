# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardUsage do
  subject(:usage) do
    described_class.new(contract_rate_card:, obligation:, rate_phase: nil, fees:)
  end

  let(:contract_rate_card) { build_stubbed(:contract_rate_card) }
  let(:obligation) { Billing::Obligation.new(cycle:, segments:, billing_at: nil, terms: nil) }
  let(:cycle) { Billing::Cycle.new(index: 0, started_at: segments.first.started_at, ended_at: segments.last.ended_at, phase:, calendar: nil) }
  let(:phase) { Billing::Phase.new(code: nil, billing_interval_cycle_count: nil, rate_override:) }
  let(:rate_override) { nil }
  let(:rate) { build_stubbed(:rate_card_rate, rate_properties: {"amount" => "2"}) }
  let(:segments) do
    [
      Billing::Segments::Segment.new(started_at: Time.utc(2027, 2, 1), ended_at: Time.utc(2027, 2, 15), rate:),
      Billing::Segments::Segment.new(started_at: Time.utc(2027, 2, 15), ended_at: Time.utc(2027, 3, 1, 0, 0, Rational(123456, 1_000_000)),
        rate: build_stubbed(:rate_card_rate, rate_properties: {"amount" => "5"}))
    ]
  end
  let(:fees) do
    [
      build_stubbed(:fee, units: BigDecimal("2.5"), events_count: 3, amount_cents: 250, taxes_amount_cents: 50),
      build_stubbed(:fee, units: BigDecimal(1), events_count: nil, amount_cents: 100, taxes_amount_cents: 20)
    ]
  end

  it "sums its fees" do
    expect(usage).to have_attributes(
      units: BigDecimal("3.5"), events_count: 3, amount_cents: 350, taxes_amount_cents: 70, rate_source: "rate"
    )
  end

  it "retains the selected obligation" do
    expect(usage.obligation).to eq(obligation)
  end

  it "exposes the complete coverage and first segment pricing metadata" do
    expect(usage).not_to respond_to(:billing_segments)
    expect(usage.members).to eq(%i[contract_rate_card obligation rate_phase fees])
    expect(usage).to have_attributes(
      started_at: Time.utc(2027, 2, 1), ended_at: Time.utc(2027, 3, 1, 0, 0, Rational(123455, 1_000_000)),
      rate:, rate_properties: {"amount" => "2"}
    )
  end

  context "without fees" do
    let(:fees) { [] }

    it "sums to zero, with decimal units" do
      expect(usage.units).to eq(BigDecimal(0))
      expect(usage.units).to be_a(BigDecimal)
      expect(usage).to have_attributes(events_count: 0, amount_cents: 0, taxes_amount_cents: 0)
    end
  end

  context "when a phase override prices the window" do
    let(:rate_override) { build_stubbed(:rate_override, rate_properties: {"amount" => "1"}) }

    it "uses the override for pricing metadata and its source" do
      expect(usage).to have_attributes(rate: rate_override, rate_properties: {"amount" => "1"}, rate_source: "phase_override")
    end
  end
end
