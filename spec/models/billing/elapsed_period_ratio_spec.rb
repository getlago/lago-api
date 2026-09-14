# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::ElapsedPeriodRatio do
  describe ".calculate" do
    subject(:ratio) { described_class.calculate(from_date:, to_date:, current_date:, duration_in_days:) }

    let(:from_date) { Date.new(2026, 1, 15) }
    let(:to_date) { Date.new(2026, 1, 31) }
    let(:duration_in_days) { 31 }

    {
      "before the first day" => [Date.new(2026, 1, 14), 0.0],
      "on the first day" => [Date.new(2026, 1, 15), 1.fdiv(31)],
      "during a shortened window" => [Date.new(2026, 1, 20), 6.fdiv(31)],
      "on the last day" => [Date.new(2026, 1, 31), 1.0],
      "after the last day" => [Date.new(2026, 2, 1), 1.0]
    }.each do |description, (date, expected_ratio)|
      context description do
        let(:current_date) { date }

        it "returns the inclusive-day progress" do
          expect(ratio).to eq(expected_ratio)
        end
      end
    end

    context "without an explicit denominator" do
      let(:duration_in_days) { nil }
      let(:current_date) { Date.new(2026, 1, 20) }

      it "uses the inclusive window duration" do
        expect(ratio).to eq(6.fdiv(17))
      end
    end

    context "when elapsed days exceed the supplied denominator" do
      let(:duration_in_days) { 2 }
      let(:current_date) { Date.new(2026, 1, 20) }

      it "caps progress at one" do
        expect(ratio).to eq(1.0)
      end
    end

    context "with a single-day window" do
      let(:to_date) { from_date }
      let(:current_date) { from_date }
      let(:duration_in_days) { nil }

      it "is complete on that day" do
        expect(ratio).to eq(1.0)
      end
    end
  end
end
