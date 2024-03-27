# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetricsQuery, type: :query do
  subject(:billable_metric_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric_first) { create(:billable_metric, organization:, name: "defgh", code: "11") }
  let(:billable_metric_second) { create(:billable_metric, organization:, name: "abcde", code: "22") }
  let(:billable_metric_third) { create(:billable_metric, organization:, name: "presuv", code: "33") }
  let(:billable_metric_fourth) { create(:unique_count_billable_metric, organization:, name: "qwerty", code: "44") }

  before do
    billable_metric_first
    billable_metric_second
    billable_metric_third
    billable_metric_fourth
  end

  it "returns all billable metrics" do
    result = billable_metric_query.call(
      search_term: nil,
      page: 1,
      limit: 10
    )

    returned_ids = result.billable_metrics.pluck(:id)

    aggregate_failures do
      expect(result.billable_metrics.count).to eq(4)
      expect(returned_ids).to include(billable_metric_first.id)
      expect(returned_ids).to include(billable_metric_second.id)
      expect(returned_ids).to include(billable_metric_third.id)
      expect(returned_ids).to include(billable_metric_fourth.id)
    end
  end

  context "when searching for recurring billable metrics" do
    let(:billable_metric_recurring) do
      create(
        :billable_metric,
        organization:,
        aggregation_type: "unique_count_agg",
        name: "defghz",
        code: "55",
        field_name: "test",
        recurring: true
      )
    end

    before { billable_metric_recurring }

    it "returns 1 billable metric" do
      result = billable_metric_query.call(
        search_term: nil,
        page: 1,
        limit: 10,
        filters: {
          recurring: true
        }
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(1)
        expect(returned_ids).not_to include(billable_metric_first.id)
        expect(returned_ids).not_to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
        expect(returned_ids).not_to include(billable_metric_fourth.id)
        expect(returned_ids).to include(billable_metric_recurring.id)
      end
    end
  end

  context "when searching for count_agg aggregation type" do
    it "returns 3 billable metrics" do
      result = billable_metric_query.call(
        search_term: nil,
        page: 1,
        limit: 10,
        filters: {
          aggregation_types: ["count_agg"]
        }
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(3)
        expect(returned_ids).to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).to include(billable_metric_third.id)
        expect(returned_ids).not_to include(billable_metric_fourth.id)
      end
    end
  end

  context "when searching for max_agg aggregation type" do
    it "returns 0 billable metrics" do
      result = billable_metric_query.call(
        search_term: nil,
        page: 1,
        limit: 10,
        filters: {
          aggregation_types: ["max_agg"]
        }
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(0)
        expect(returned_ids).not_to include(billable_metric_first.id)
        expect(returned_ids).not_to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
        expect(returned_ids).not_to include(billable_metric_fourth.id)
      end
    end
  end

  context "when searching for /de/ term" do
    it "returns only two billable metrics" do
      result = billable_metric_query.call(
        search_term: "de",
        page: 1,
        limit: 10
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(2)
        expect(returned_ids).to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
      end
    end
  end

  context "when searching for /de/ term and filtering by id" do
    it "returns only one billable metric" do
      result = billable_metric_query.call(
        search_term: "de",
        page: 1,
        limit: 10,
        filters: {
          ids: [billable_metric_second.id]
        }
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(1)
        expect(returned_ids).not_to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
      end
    end
  end
end
