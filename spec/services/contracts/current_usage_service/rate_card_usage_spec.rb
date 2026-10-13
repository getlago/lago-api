# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::CurrentUsageService::RateCardUsage do
  subject(:usage) do
    described_class.new(contract_rate_card:, billing_segment:, rate_phase: nil, fees:, invoice_id: nil)
  end

  let(:contract_rate_card) { build_stubbed(:contract_rate_card) }
  let(:rate_override) { nil }
  let(:billing_segment) { build_stubbed(:billing_segment, contract_rate_card:, rate_override:) }
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

  context "without fees" do
    let(:fees) { [] }

    it "sums to zero, with decimal units" do
      expect(usage.units).to eq(BigDecimal(0))
      expect(usage.units).to be_a(BigDecimal)
      expect(usage).to have_attributes(events_count: 0, amount_cents: 0, taxes_amount_cents: 0)
    end
  end

  context "when a phase override prices the window" do
    let(:rate_override) { build_stubbed(:rate_override) }

    it "reports the phase override as the rate source" do
      expect(usage.rate_source).to eq("phase_override")
    end
  end
end
