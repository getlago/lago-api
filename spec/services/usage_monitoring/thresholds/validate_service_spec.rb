# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::Thresholds::ValidateService do
  subject(:result) { described_class.call(thresholds:) }

  let(:thresholds) do
    [
      {code: "warn", value: "1000000"},
      {code: "high", value: 2_000_000, notify_on: %w[triggered resolved]},
      {code: "every_500k", value: "500000", recurring: true}
    ]
  end

  it "accepts the thresholds" do
    expect(result).to be_success
  end

  [nil, []].each do |value|
    context "with thresholds #{value.inspect}" do
      let(:thresholds) { value }

      it "returns value_is_mandatory" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
      end
    end
  end

  [{value: 10}, "10", [{value: 1}, "10"]].each do |value|
    context "with thresholds #{value.inspect}" do
      let(:thresholds) { value }

      it "returns value_is_invalid" do
        expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      end
    end
  end

  context "with more thresholds than the limit" do
    let(:thresholds) { Array.new(21) { {value: it + 1} } }

    it "returns too_many_thresholds with the limit" do
      expect(result.error.messages).to eq({thresholds: ["too_many_thresholds"]})
      expect(result.error.meta).to eq({thresholds: {max_items: 20}})
    end
  end

  context "with as many thresholds as the limit" do
    let(:thresholds) { Array.new(20) { {value: it + 1} } }

    it "accepts them" do
      expect(result).to be_success
    end
  end

  context "without a value" do
    let(:thresholds) { [{value: 1}, {code: "warn"}] }

    it "returns value_is_mandatory" do
      expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
    end
  end

  [1, -1, 1.5, "1.5", " 12 ", "1e3", "-0.5", "9999999999999999999999999.99999"].each do |value|
    context "with value #{value.inspect}" do
      let(:thresholds) { [{value:}] }

      it "accepts it" do
        expect(result).to be_success
      end
    end
  end

  ["abc", "", "0x1A", "Infinity", "NaN", Float::INFINITY, 1e30, "10000000000000000000000000", "9999999999999999999999999.999995", true, [1], {amount: 1}].each do |value|
    context "with value #{value.inspect}" do
      let(:thresholds) { [{value:}] }

      it "returns value_is_invalid" do
        expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      end
    end
  end

  [0, -10, "0", "0.000001"].each do |value|
    context "with a recurring value of #{value.inspect}" do
      let(:thresholds) { [{value:, recurring: true}] }

      it "returns recurring_value_is_negative" do
        expect(result.error.messages).to eq({thresholds: ["recurring_value_is_negative"]})
      end
    end
  end

  context "with the same value sent as a number and as a string" do
    let(:thresholds) { [{value: 2000}, {value: "2000.0"}] }

    it "returns duplicate_threshold_values" do
      expect(result.error.messages).to eq({thresholds: ["duplicate_threshold_values"]})
    end
  end

  context "with values that round to the same 5 decimals" do
    let(:thresholds) { [{value: "1.000001"}, {value: "1.000002"}] }

    it "returns duplicate_threshold_values" do
      expect(result.error.messages).to eq({thresholds: ["duplicate_threshold_values"]})
    end
  end

  ["-0", -0.0, "-0.000001"].each do |value|
    context "with 0 and #{value.inspect}" do
      let(:thresholds) { [{value: 0}, {value:}] }

      it "returns duplicate_threshold_values" do
        expect(result.error.messages).to eq({thresholds: ["duplicate_threshold_values"]})
      end
    end
  end

  context "with the same value once recurring and once not" do
    let(:thresholds) { [{value: 2000}, {value: 2000, recurring: true}] }

    it "accepts them" do
      expect(result).to be_success
    end
  end

  [
    {code: ["warn"], value: 10},
    {code: {text: "warn"}, value: 10},
    {value: 10, recurring: [true]},
    {value: 10, recurring: {every: true}},
    {code: "warn", value: 10, recurring: [false], notify_on: %w[triggered resolved]}
  ].each do |threshold|
    context "with #{threshold.inspect}" do
      let(:thresholds) { [{value: 1}, threshold] }

      it "returns value_is_invalid" do
        expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      end
    end
  end

  context "with two recurring thresholds" do
    let(:thresholds) { [{value: 10, recurring: true}, {value: 20, recurring: true}] }

    it "returns value_is_invalid" do
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
    end
  end

  describe "notify_on" do
    let(:thresholds) { [{value: 1}, {code: "warn", value: 10, notify_on:}] }

    [%w[triggered], %w[triggered resolved], %w[resolved triggered], %i[triggered resolved], nil].each do |value|
      context "with #{value.inspect}" do
        let(:notify_on) { value }

        it "accepts it" do
          expect(result).to be_success
        end
      end
    end

    ["resolved", %w[triggered unknown], {triggered: true}].each do |value|
      context "with #{value.inspect}" do
        let(:notify_on) { value }

        it "returns value_is_invalid" do
          expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
        end
      end
    end

    [[], %w[resolved]].each do |value|
      context "with #{value.inspect}" do
        let(:notify_on) { value }

        it "returns triggered_is_mandatory" do
          expect(result.error.messages).to eq({thresholds: ["triggered_is_mandatory"]})
        end
      end
    end

    context "when a recurring threshold opts in to resolved" do
      let(:thresholds) { [{value: 10, recurring: true, notify_on: %w[triggered resolved]}] }

      it "returns recurring_not_supported" do
        expect(result.error.messages).to eq({thresholds: ["recurring_not_supported"]})
      end
    end

    context "when a threshold without a code opts in to resolved" do
      let(:thresholds) { [{value: 10, notify_on: %w[triggered resolved]}] }

      it "returns value_is_mandatory" do
        expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
      end
    end

    context "when a threshold opts in to resolved with a code another threshold has" do
      let(:thresholds) { [{code: "warn", value: 10}, {code: "warn", value: 20, notify_on: %w[triggered resolved]}] }

      it "returns duplicate_threshold_codes" do
        expect(result.error.messages).to eq({thresholds: ["duplicate_threshold_codes"]})
      end
    end

    context "when thresholds that do not opt in share a code" do
      let(:thresholds) { [{code: "warn", value: 10}, {code: "warn", value: 20}] }

      it "accepts them" do
        expect(result).to be_success
      end
    end
  end

  context "with several errors" do
    let(:thresholds) { [{value: "abc"}, {value: 10}, {value: 10, notify_on: %w[resolved]}] }

    it "returns the first one" do
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
    end
  end
end
