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

      it "returns value_is_mandatory on the list" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
      end
    end
  end

  [{value: 10}, "10"].each do |value|
    context "with thresholds #{value.inspect}" do
      let(:thresholds) { value }

      it "returns value_is_invalid on the list" do
        expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
      end
    end
  end

  context "with items that are not objects" do
    let(:thresholds) { [{value: 1}, "10", [{value: 2}]] }

    it "returns value_is_invalid on the first of them" do
      expect(result.error.messages).to eq({"thresholds[1]": ["value_is_invalid"]})
    end
  end

  context "with more thresholds than the limit" do
    let(:thresholds) { Array.new(21) { {value: it + 1} } }

    it "returns too_many_thresholds with the limit, on the list" do
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

    it "returns value_is_mandatory on its value" do
      expect(result.error.messages).to eq({"thresholds[1].value": ["value_is_mandatory"]})
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
      let(:thresholds) { [{value: 1}, {value:}] }

      it "returns value_is_invalid on its value" do
        expect(result.error.messages).to eq({"thresholds[1].value": ["value_is_invalid"]})
      end
    end
  end

  [0, -10, "0", "0.000001"].each do |value|
    context "with a recurring value of #{value.inspect}" do
      let(:thresholds) { [{value: 1}, {value:, recurring: true}] }

      it "returns recurring_value_is_negative on its value" do
        expect(result.error.messages).to eq({"thresholds[1].value": ["recurring_value_is_negative"]})
      end
    end
  end

  context "with the same value sent as a number and as a string" do
    let(:thresholds) { [{value: 2000}, {value: "2000.0"}] }

    it "returns duplicate_threshold_values on the later one" do
      expect(result.error.messages).to eq({"thresholds[1].value": ["duplicate_threshold_values"]})
    end
  end

  context "with the value of a threshold two places before" do
    let(:thresholds) { [{value: 5}, {value: 10}, {value: 5}] }

    it "returns duplicate_threshold_values on the later one" do
      expect(result.error.messages).to eq({"thresholds[2].value": ["duplicate_threshold_values"]})
    end
  end

  context "with values that round to the same 5 decimals" do
    let(:thresholds) { [{value: "1.000001"}, {value: "1.000002"}] }

    it "returns duplicate_threshold_values on the later one" do
      expect(result.error.messages).to eq({"thresholds[1].value": ["duplicate_threshold_values"]})
    end
  end

  ["-0", -0.0, "-0.000001"].each do |value|
    context "with 0 and #{value.inspect}" do
      let(:thresholds) { [{value: 0}, {value:}] }

      it "returns duplicate_threshold_values on the later one" do
        expect(result.error.messages).to eq({"thresholds[1].value": ["duplicate_threshold_values"]})
      end
    end
  end

  context "with the same value once recurring and once not" do
    let(:thresholds) { [{value: 2000}, {value: 2000, recurring: true}] }

    it "accepts them" do
      expect(result).to be_success
    end
  end

  {
    {code: ["warn"], value: 10} => :code,
    {code: {text: "warn"}, value: 10} => :code,
    {value: 10, recurring: [true]} => :recurring,
    {value: 10, recurring: {every: true}} => :recurring,
    {code: "warn", value: 10, recurring: [false], notify_on: %w[triggered resolved]} => :recurring
  }.each do |threshold, field|
    context "with #{threshold.inspect}" do
      let(:thresholds) { [{value: 1}, threshold] }

      it "returns value_is_invalid on its #{field}" do
        expect(result.error.messages).to eq({"thresholds[1].#{field}": ["value_is_invalid"]})
      end
    end
  end

  context "with two recurring thresholds" do
    let(:thresholds) { [{value: 5}, {value: 10, recurring: true}, {value: 20, recurring: true}] }

    it "returns value_is_invalid on the second recurring one's recurring" do
      expect(result.error.messages).to eq({"thresholds[2].recurring": ["value_is_invalid"]})
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

        it "returns value_is_invalid on its notify_on" do
          expect(result.error.messages).to eq({"thresholds[1].notify_on": ["value_is_invalid"]})
        end
      end
    end

    [[], %w[resolved]].each do |value|
      context "with #{value.inspect}" do
        let(:notify_on) { value }

        it "returns triggered_is_mandatory on its notify_on" do
          expect(result.error.messages).to eq({"thresholds[1].notify_on": ["triggered_is_mandatory"]})
        end
      end
    end

    context "when a recurring threshold opts in to resolved" do
      let(:thresholds) { [{value: 5}, {value: 10, recurring: true, notify_on: %w[triggered resolved]}] }

      it "returns recurring_not_supported on its notify_on" do
        expect(result.error.messages).to eq({"thresholds[1].notify_on": ["recurring_not_supported"]})
      end
    end

    context "when a threshold without a code opts in to resolved" do
      let(:thresholds) { [{value: 5}, {value: 10, notify_on: %w[triggered resolved]}] }

      it "returns value_is_mandatory on its code" do
        expect(result.error.messages).to eq({"thresholds[1].code": ["value_is_mandatory"]})
      end
    end

    context "when a threshold opts in to resolved with the code of an earlier threshold" do
      let(:thresholds) { [{code: "warn", value: 10}, {code: "warn", value: 20, notify_on: %w[triggered resolved]}] }

      it "returns duplicate_threshold_codes on the later one's code" do
        expect(result.error.messages).to eq({"thresholds[1].code": ["duplicate_threshold_codes"]})
      end
    end

    context "when a later threshold takes the code of one that opts in to resolved" do
      let(:thresholds) { [{code: "warn", value: 10, notify_on: %w[triggered resolved]}, {value: 15}, {code: "warn", value: 20}] }

      it "returns duplicate_threshold_codes on the later one's code" do
        expect(result.error.messages).to eq({"thresholds[2].code": ["duplicate_threshold_codes"]})
      end
    end

    context "when thresholds that do not opt in share a code" do
      let(:thresholds) { [{code: "warn", value: 10}, {code: "warn", value: 20}] }

      it "accepts them" do
        expect(result).to be_success
      end
    end
  end

  {
    "a code that is not a single value" => [[{value: 1}, {value: 2, code: ["a"]}, {value: 3, code: ["b"]}], {"thresholds[1].code": ["value_is_invalid"]}],
    "no value" => [[{value: 1}, {code: "a"}, {code: "b"}], {"thresholds[1].value": ["value_is_mandatory"]}],
    "a value that is not a number" => [[{value: 1}, {value: "abc"}, {value: "xyz"}], {"thresholds[1].value": ["value_is_invalid"]}],
    "a negative recurring value" => [[{value: 1}, {value: -1, recurring: true}, {value: -2, recurring: true}], {"thresholds[1].value": ["recurring_value_is_negative"]}],
    "an unknown notify_on" => [[{value: 1}, {value: 2, notify_on: %w[unknown]}, {value: 3, notify_on: %w[other]}], {"thresholds[1].notify_on": ["value_is_invalid"]}],
    "a notify_on without triggered" => [[{value: 1}, {value: 2, notify_on: []}, {value: 3, notify_on: %w[resolved]}], {"thresholds[1].notify_on": ["triggered_is_mandatory"]}],
    "an opt-in to resolved without a code" => [[{value: 1}, {value: 2, notify_on: %w[triggered resolved]}, {value: 3, notify_on: %w[triggered resolved]}], {"thresholds[1].code": ["value_is_mandatory"]}]
  }.each do |error, (list, messages)|
    context "with two thresholds that have #{error}" do
      let(:thresholds) { list }

      it "returns the error on the first of them" do
        expect(result.error.messages).to eq(messages)
      end
    end
  end

  context "with several errors" do
    # The value check runs before the notify_on check, so it wins although its threshold comes later
    let(:thresholds) { [{value: 10}, {value: 20, notify_on: %w[resolved]}, {value: "abc"}, {value: "xyz"}] }

    it "returns the first check that fails, on the first threshold that fails it" do
      expect(result.error.messages).to eq({"thresholds[2].value": ["value_is_invalid"]})
    end
  end
end
