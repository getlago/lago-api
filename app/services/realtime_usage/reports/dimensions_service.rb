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
        validate_billable_metric(billable_metric) if result.success?
        validate_dimension_keys(dimension_keys) if result.success?
        return result unless result.success?

        rescue_read_errors do
          dimension_key = dimension_key_for([billable_metric.code])
          page_rows = ranked_dimensions(
            billable_metrics: [billable_metric],
            dimension_key:,
            dimension_keys:,
            limit:,
            offset: (page - 1) * limit
          )
          periods = periods_by_key(dimension_key, page_rows.map(&:second))

          result.total_count = page_rows.first&.last ||
            dimensions_count(billable_metric:, dimension_key:, dimension_keys:)
          result.page = page
          result.limit = limit
          result.dimensions = page_rows.map do |_code, key, units|
            dimension = dimension_key.dimension(key)
            points = window.periods.map do |period|
              Point.new(Time.zone.at(period), periods.dig(period, key) || BigDecimal(0))
            end

            Row.new(key, dimension.name, dimension.values, units, points)
          end
          result
        end
      end

      private

      attr_reader :billable_metric, :dimension_keys, :page, :limit

      def periods_by_key(dimension_key, keys)
        return {} if keys.empty?

        period_rows(billable_metrics: [billable_metric], dimension_key:, keys:)
          .each_with_object({}) do |(_code, period, key, units), by_period|
            (by_period[period] ||= {})[key] = units
          end
      end
    end
  end
end
