# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::NullAggregator do
  describe "#per_event_aggregation" do
    subject(:null_aggregator) { described_class.new }

    it "returns a PerEventAggregationResult with an empty event_aggregation" do
      result = null_aggregator.per_event_aggregation

      expect(result).to be_a(BillableMetrics::Aggregations::BaseService::PerEventAggregationResult)
      expect(result.event_aggregation).to eq([])
    end

    it "accepts keyword arguments without raising" do
      result = null_aggregator.per_event_aggregation(
        exclude_event: true,
        include_event_value: true,
        grouped_by_values: {"region" => "eu"}
      )

      expect(result.event_aggregation).to eq([])
    end
  end
end
