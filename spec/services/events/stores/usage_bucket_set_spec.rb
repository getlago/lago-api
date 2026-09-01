# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::UsageBucketSet do
  subject(:bucket_set) { described_class.new(totals:, grouped_totals:) }

  let(:totals) { {["charge_1", ""] => described_class::Totals.new(units: BigDecimal("42.5"), events_count: 7)} }
  let(:grouped_totals) do
    {
      ["charge_1", ""] => [
        [{"region" => "us"}, described_class::Totals.new(units: BigDecimal("30"), events_count: 5)],
        [{"region" => "eu"}, described_class::Totals.new(units: BigDecimal("12.5"), events_count: 2)]
      ]
    }
  end

  describe "#empty?" do
    it "is false when the set carries rows" do
      expect(bucket_set).not_to be_empty
    end

    context "when built with no rows" do
      it "is true" do
        expect(described_class.new).to be_empty
      end
    end
  end

  describe "#aggregation_result_for" do
    it "reports the units as the value and the events count alongside" do
      result = bucket_set.aggregation_result_for(charge_id: "charge_1", charge_filter_id: "")

      expect([result.value, result.events_count]).to eq([BigDecimal("42.5"), 7])
    end

    it "is zero for a charge the buckets do not carry" do
      result = bucket_set.aggregation_result_for(charge_id: "charge_2", charge_filter_id: "")

      expect([result.value, result.events_count]).to eq([BigDecimal(0), 0])
    end

    it "distinguishes charge filters of the same charge" do
      result = bucket_set.aggregation_result_for(charge_id: "charge_1", charge_filter_id: "filter_1")

      expect(result.value).to eq(0)
    end

    context "with a count metric, whose events the pipeline values at 1 apiece" do
      let(:totals) { {["charge_1", ""] => described_class::Totals.new(units: BigDecimal("7"), events_count: 7)} }

      it "reports the units, which already are the count" do
        result = bucket_set.aggregation_result_for(charge_id: "charge_1", charge_filter_id: "")

        expect([result.value, result.events_count]).to eq([7, 7])
      end
    end
  end

  describe "#grouped_aggregation_results_for" do
    it "returns one result per group" do
      results = bucket_set.grouped_aggregation_results_for(charge_id: "charge_1", charge_filter_id: "")

      expect(results.map { |r| [r.groups, r.value, r.events_count] }).to match_array(
        [
          [{"region" => "us"}, BigDecimal("30"), 5],
          [{"region" => "eu"}, BigDecimal("12.5"), 2]
        ]
      )
    end

    it "is empty for a charge the buckets do not carry" do
      expect(bucket_set.grouped_aggregation_results_for(charge_id: "charge_2", charge_filter_id: "")).to eq([])
    end
  end

  describe "immutability" do
    it "is frozen so a computation cannot rewrite the window it read" do
      expect(bucket_set).to be_frozen
    end

    it "copies the rows, so the builder keeps writing to its own accumulators" do
      bucket_set

      expect { totals[["charge_2", ""]] = described_class::Totals.new(units: BigDecimal("1"), events_count: 1) }
        .not_to raise_error
      expect { grouped_totals[["charge_2", ""]] = [] }.not_to raise_error

      expect(bucket_set.aggregation_result_for(charge_id: "charge_2", charge_filter_id: "").value).to eq(0)
    end
  end
end
