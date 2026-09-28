# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::UsageBucketSet do
  subject(:bucket_set) { described_class.new(totals:, grouped_totals:) }

  def build_totals(units, events_count, aggregation_type: "sum_agg", last_event_at: Time.current, precise_total_amount_cents: BigDecimal(0))
    described_class::Totals.new(aggregation_type:, units:, events_count:, last_event_at:, precise_total_amount_cents:)
  end

  let(:totals) { {["charge_1", ""] => build_totals(BigDecimal("42.5"), 7)} }
  let(:grouped_totals) do
    {
      ["charge_1", ""] => [
        [{"region" => "us"}, build_totals(BigDecimal(30), 5)],
        [{"region" => "eu"}, build_totals(BigDecimal("12.5"), 2)]
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

  describe "#charge_filter_ids_for" do
    let(:totals) do
      {
        ["charge_1", ""] => build_totals(BigDecimal("42.5"), 7),
        ["charge_1", "filter_1"] => build_totals(BigDecimal(3), 3),
        ["charge_2", "filter_2"] => build_totals(BigDecimal(1), 1)
      }
    end

    it "lists the filters of that charge only" do
      expect(bucket_set.charge_filter_ids_for(charge_id: "charge_1")).to match_array(["", "filter_1"])
    end

    it "is empty for a charge the buckets do not carry" do
      expect(bucket_set.charge_filter_ids_for(charge_id: "charge_3")).to be_empty
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
      let(:totals) { {["charge_1", ""] => build_totals(BigDecimal(7), 7, aggregation_type: "count_agg")} }

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
          [{"region" => "us"}, BigDecimal(30), 5],
          [{"region" => "eu"}, BigDecimal("12.5"), 2]
        ]
      )
    end

    it "is empty for a charge the buckets do not carry" do
      expect(bucket_set.grouped_aggregation_results_for(charge_id: "charge_2", charge_filter_id: "")).to eq([])
    end
  end

  describe "#precise_total_amount_cents_for" do
    let(:totals) do
      {["charge_1", ""] => build_totals(BigDecimal("42.5"), 7, precise_total_amount_cents: BigDecimal("1234.000000000000001"))}
    end

    it "reports the summed precise amount of the charge filter" do
      expect(bucket_set.precise_total_amount_cents_for(charge_id: "charge_1", charge_filter_id: ""))
        .to eq(BigDecimal("1234.000000000000001"))
    end

    it "is zero for a charge the buckets do not carry" do
      expect(bucket_set.precise_total_amount_cents_for(charge_id: "charge_2", charge_filter_id: "")).to eq(0)
    end
  end

  describe "#grouped_precise_total_amount_cents_for" do
    let(:grouped_totals) do
      {
        ["charge_1", ""] => [
          [{"region" => "us"}, build_totals(BigDecimal(30), 5, precise_total_amount_cents: BigDecimal("300.5"))],
          [{"region" => "eu"}, build_totals(BigDecimal("12.5"), 2, precise_total_amount_cents: BigDecimal(125))]
        ]
      }
    end

    it "returns the groups and their amount in the shape the events store returns" do
      expect(bucket_set.grouped_precise_total_amount_cents_for(charge_id: "charge_1", charge_filter_id: "")).to match_array(
        [
          {groups: {"region" => "us"}, value: BigDecimal("300.5")},
          {groups: {"region" => "eu"}, value: BigDecimal(125)}
        ]
      )
    end

    it "is empty for a charge the buckets do not carry" do
      expect(bucket_set.grouped_precise_total_amount_cents_for(charge_id: "charge_2", charge_filter_id: "")).to eq([])
    end
  end

  describe "Totals" do
    it "defaults the precise amount to zero, as the pipeline writes on every type but sum" do
      expect(described_class::Totals.new(aggregation_type: "max_agg", units: 1, events_count: 1, last_event_at: Time.current).precise_total_amount_cents)
        .to eq(0)
    end
  end

  describe "Totals#combine" do
    let(:earlier) { Time.current - 1.hour }

    it "adds the units of a sum metric" do
      combined = build_totals(BigDecimal(10), 2).combine(build_totals(BigDecimal(5), 1))

      expect([combined.units, combined.events_count]).to eq([BigDecimal(15), 3])
    end

    it "keeps the largest units of a max metric" do
      combined = build_totals(BigDecimal(10), 2, aggregation_type: "max_agg")
        .combine(build_totals(BigDecimal(5), 1, aggregation_type: "max_agg"))

      expect([combined.units, combined.events_count]).to eq([BigDecimal(10), 3])
    end

    it "keeps the units of the most recent row of a latest metric" do
      combined = build_totals(BigDecimal(10), 2, aggregation_type: "latest_agg", last_event_at: earlier)
        .combine(build_totals(BigDecimal(5), 1, aggregation_type: "latest_agg"))

      expect([combined.units, combined.events_count]).to eq([BigDecimal(5), 3])
    end

    it "ignores an older row of a latest metric" do
      combined = build_totals(BigDecimal(10), 2, aggregation_type: "latest_agg")
        .combine(build_totals(BigDecimal(5), 1, aggregation_type: "latest_agg", last_event_at: earlier))

      expect(combined.units).to eq(BigDecimal(10))
    end

    it "adds the precise amounts" do
      combined = build_totals(BigDecimal(10), 2, precise_total_amount_cents: BigDecimal("100.25"))
        .combine(build_totals(BigDecimal(5), 1, precise_total_amount_cents: BigDecimal("0.75")))

      expect(combined.precise_total_amount_cents).to eq(BigDecimal(101))
    end

    it "carries the most recent event time over, so a third row compares against it" do
      combined = build_totals(BigDecimal(10), 2, last_event_at: earlier)
        .combine(build_totals(BigDecimal(5), 1))

      expect(combined.last_event_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "immutability" do
    it "is frozen so a computation cannot rewrite the window it read" do
      expect(bucket_set).to be_frozen
    end

    it "copies the rows, so the builder keeps writing to its own accumulators" do
      bucket_set

      expect { totals[["charge_2", ""]] = build_totals(BigDecimal(1), 1) }
        .not_to raise_error
      expect { grouped_totals[["charge_2", ""]] = [] }.not_to raise_error

      expect(bucket_set.aggregation_result_for(charge_id: "charge_2", charge_filter_id: "").value).to eq(0)
    end
  end
end
