# frozen_string_literal: true

module RealtimeUsage
  # The billable metrics the real-time usage reports can answer, a page at a time. A page is read
  # by a single ClickHouse aggregation, so its size is bounded.
  class BillableMetricsQuery < BaseQuery
    Result = BaseResult[:billable_metrics]

    DEFAULT_LIMIT = 20
    MAX_LIMIT = 100

    def call
      billable_metrics = BillableMetric
        .where(organization:, aggregation_type: SUPPORTED_AGGREGATION_TYPES, recurring: false)
        .order(:name, :id)

      result.billable_metrics = paginate(billable_metrics)
      result
    end

    private

    def pagination
      super&.tap { |pagination| pagination.limit = (pagination.limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT) }
    end
  end
end
