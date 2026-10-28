# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::BillableMetricsQuery do
  subject(:result) { described_class.call(organization:, pagination:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:tokens) { create(:billable_metric, organization:, name: "Tokens", aggregation_type: "sum_agg", field_name: "value") }
  let_it_be(:api_calls) { create(:billable_metric, organization:, name: "API calls", aggregation_type: "count_agg") }
  let_it_be(:seats) { create(:billable_metric, organization:, name: "Seats", aggregation_type: "max_agg", field_name: "value") }

  let(:pagination) { {page: 1, limit: 2} }

  before_all do
    create(:billable_metric, organization:, name: "Users", aggregation_type: "unique_count_agg", field_name: "value")
    create(:billable_metric, organization:, name: "Storage", aggregation_type: "sum_agg", field_name: "value", recurring: true)
    create(:billable_metric, organization: create(:organization), name: "Another", aggregation_type: "count_agg")
  end

  it "pages through the metrics the buckets serve, by name" do
    expect(result.billable_metrics).to eq([api_calls, seats])
    expect(result.billable_metrics.total_count).to eq(3)
  end

  context "without a limit" do
    let(:pagination) { {page: 1, limit: nil} }

    it "uses the default one" do
      expect(result.billable_metrics.limit_value).to eq(described_class::DEFAULT_LIMIT)
    end
  end

  context "with a limit above the maximum" do
    let(:pagination) { {page: 1, limit: 10_000} }

    it "caps it" do
      expect(result.billable_metrics.limit_value).to eq(described_class::MAX_LIMIT)
      expect(result.billable_metrics).to eq([api_calls, seats, tokens])
    end
  end
end
