# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::BaseService do
  describe ".empty_result" do
    subject(:empty_result) { described_class.empty_result(**args) }

    context "without arguments" do
      let(:args) { {} }

      it "returns a result with zero values" do
        expect(empty_result.aggregation).to eq(0)
        expect(empty_result.count).to eq(0)
        expect(empty_result.current_usage_units).to eq(0)
        expect(empty_result.options).to eq({running_total: []})
        expect(empty_result.grouped_by).to be_nil
      end
    end

    context "with a custom result" do
      let(:custom_result) { described_class::Result.new }

      it "populates the provided result" do
        returned = described_class.empty_result(custom_result)

        expect(returned).to eq(custom_result)
        expect(returned.aggregation).to eq(0)
        expect(returned.count).to eq(0)
        expect(returned.current_usage_units).to eq(0)
        expect(returned.options).to eq({running_total: []})
      end
    end

    context "with grouped_by_keys" do
      let(:args) { {grouped_by_keys: %w[region plan]} }

      it "sets grouped_by with nil values for each key" do
        expect(empty_result.grouped_by).to eq({"region" => nil, "plan" => nil})
        expect(empty_result.aggregation).to eq(0)
        expect(empty_result.count).to eq(0)
        expect(empty_result.current_usage_units).to eq(0)
        expect(empty_result.options).to eq({running_total: []})
      end
    end

    context "with empty grouped_by_keys" do
      let(:args) { {grouped_by_keys: []} }

      it "sets grouped_by to an empty hash" do
        expect(empty_result.grouped_by).to eq({})
        expect(empty_result.aggregation).to eq(0)
        expect(empty_result.count).to eq(0)
      end
    end
  end
end
