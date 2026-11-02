# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::ValidateApiInputService do
  subject(:result) { described_class.call(params:) }

  let(:params) { {} }

  it "accepts omitted fields" do
    expect(result).to be_success
  end

  {
    aggregation_type: BillableMetric::AGGREGATION_TYPES.keys.map(&:to_s),
    rounding_function: [nil, "round", "ceil", "floor"],
    weighted_interval: [nil, "seconds"],
    recurring: [true, false, "true", "false", 0, 1, "0", "1"],
    rounding_precision: [nil, 0, 2, -2, "2", "-2", "+2", "010"],
    expression: [nil, "event.properties.units"]
  }.each do |field, values|
    values.each do |value|
      context "with #{field} set to #{value.inspect}" do
        let(:params) { {field => value} }

        it "accepts the value" do
          expect(result).to be_success
        end
      end
    end
  end

  {
    aggregation_type: [nil, "unknown", 123, false],
    rounding_function: ["unknown", 123, false],
    weighted_interval: ["minutes", 123, false],
    recurring: [nil, "unknown"],
    rounding_precision: [false, "unknown", 1.5, 2.0, "0x10", "2_000", "1.5"],
    expression: [123, false]
  }.each do |field, values|
    values.each do |value|
      context "with invalid #{field} #{value.inspect}" do
        let(:params) { {field => value} }

        it "returns an API validation error" do
          expect(result.error.messages).to eq(field => ["value_is_invalid"])
        end
      end
    end
  end

  context "with filters" do
    let(:params) { {filters: [{key: "region", values: ["eu"]}, {key: "cloud", values: ["aws"]}]} }

    it "accepts valid filters" do
      expect(result).to be_success
    end

    context "when a filter has an empty values array" do
      let(:params) { {filters: [{key: "region", values: ["eu"]}, {key: "cloud", values: []}]} }

      it "identifies the filter by its index" do
        expect(result.error.messages).to eq("filters[1].values": ["value_is_mandatory"])
      end
    end

    context "when a filter key is repeated" do
      let(:params) { {filters: [{key: "region", values: ["eu"]}, {key: "region", values: ["us"]}]} }

      it "identifies the repeated key" do
        expect(result.error.messages).to eq("filters[1].key": ["value_already_exist"])
      end
    end

    context "when a filter has no key or values" do
      let(:params) { {filters: [{}]} }

      it "reports both fields of the filter" do
        expect(result.error.messages).to eq(
          "filters[0].key": ["value_is_mandatory"],
          "filters[0].values": ["value_is_mandatory"]
        )
      end
    end

    context "when a filter key is not a string" do
      let(:params) { {filters: [{key: 123, values: ["eu"]}]} }

      it "returns an indexed validation error" do
        expect(result.error.messages).to eq("filters[0].key": ["value_is_invalid"])
      end
    end

    context "when clearing filters" do
      let(:params) { {filters: []} }

      it "leaves reference checks to the shared write service" do
        expect(result).to be_success
      end
    end
  end
end
