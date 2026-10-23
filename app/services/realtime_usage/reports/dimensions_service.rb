# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # Every dimension of one metric, biggest first, with its units per period. Unlike the chart,
    # nothing folds: the table pages through the tail instead.
    class DimensionsService < BaseService
      Result = BaseResult[:dimensions, :total_count, :page, :limit]

      Row = Struct.new(:key, :name, :values, :units, :points)
      Point = Struct.new(:time, :units)

      DEFAULT_LIMIT = 20
      MAX_LIMIT = 100

      def initialize(billable_metric:, dimension_keys: nil, page: nil, limit: nil, **)
        @billable_metric = billable_metric
        @dimension_keys = dimension_keys.presence
        @page = [page.to_i, 1].max
        @limit = (limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

        super(**)
      end

      def call
        validate_request
        return result unless result.success?
        unless SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type)
          return result.single_validation_failure!(field: :billable_metric_code, error_code: "unsupported_aggregation_type")
        end

        rescue_read_errors do
          dimension_key = dimension_key_for([billable_metric.code])
          totals = dimension_totals(billable_metrics: [billable_metric], dimension_key:, dimension_keys:)
            .sort_by { |row| [-row[:units], row[:dimension]] }
          page_rows = totals.drop((page - 1) * limit).first(limit)
          periods = period_rows(dimension_key, page_rows.map { |row| row[:dimension] })

          result.total_count = totals.size
          result.page = page
          result.limit = limit
          result.dimensions = page_rows.map do |row|
            dimension = dimension_key.dimension(row[:dimension])
            points = window.periods.map do |period|
              Point.new(Time.zone.at(period), periods.dig(period, row[:dimension]) || BigDecimal(0))
            end

            Row.new(row[:dimension], dimension.name, dimension.values, row[:units], points)
          end
          result
        end
      end

      private

      attr_reader :billable_metric, :dimension_keys, :page, :limit

      def period_rows(dimension_key, keys)
        return {} if keys.empty?

        usage_rows(billable_metrics: [billable_metric], dimension_key:, keys:, by_period: true)
          .each_with_object({}) do |(_code, period, key, units), by_period|
            (by_period[period] ||= {})[key] = units
          end
      end
    end
  end
end
