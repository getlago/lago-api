# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::BillableSegment do
  subject(:segment) { described_class.new(**attributes) }

  let(:rate) { instance_double(RateCardRate, properties: {"amount" => "10"}) }
  let(:rate_override) { nil }

  let(:attributes) do
    {
      cycle_index: 0,
      cycle_started_at: Time.zone.parse("2026-02-01 00:00:00"),
      started_at: Time.zone.parse("2026-02-01 00:00:00"),
      ended_at: Time.zone.parse("2026-03-01 00:00:00"),
      billing_at: Time.zone.parse("2026-03-01 00:00:00"),
      rate:,
      rate_override:,
      proration_ratio: 1.0,
      rate_phase_code: nil
    }
  end

  describe "#properties" do
    it "reads the rate card's own rate" do
      expect(segment.properties).to eq({"amount" => "10"})
    end

    context "when a phase override prices the segment" do
      let(:rate_override) { instance_double(RateOverride, properties: {"amount" => "7"}) }

      it "lets the override win whole, rather than merging into the rate" do
        expect(segment.properties).to eq({"amount" => "7"})
      end
    end
  end

  describe "the pricing invariant" do
    let(:rate) { nil }

    it "refuses a segment that nothing prices" do
      expect { segment }.to raise_error(ArgumentError, /needs a rate or an override/)
    end
  end
end
